// Appended to both generated Apple hosts by apply_native_hosts.py.
private enum AppleGatewayError: Error {
  case socketFailure
  case dialFailure
}

private final class AppleLoopbackGateway: @unchecked Sendable {
  let baseURL: String
  private let node: any ApplePrivateNetworkNode
  private let destination: String
  private let lock = NSLock()
  private let queue = DispatchQueue(label: "rodplayer.private-network.gateway", qos: .utility, attributes: .concurrent)
  private let acceptGroup = DispatchGroup()
  private let workers = DispatchGroup()
  private var listenerFD: Int32
  private var closing = false
  private var connections: [UUID: AppleGatewayConnection] = [:]

  init(node: any ApplePrivateNetworkNode, metadata: ApplePrivateNetworkMetadata) throws {
    // The validated metadata, never a client request, chooses the sole upstream.
    destination = "\(metadata.homeIpv4):\(metadata.homePort)"
    self.node = node
    let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else { throw AppleGatewayError.socketFailure }
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = 0 // OS-assigned ephemeral port.
    let parsed = "127.0.0.1".withCString { inet_pton(AF_INET, $0, &address.sin_addr) }
    guard parsed == 1 else {
      Darwin.close(fd)
      throw AppleGatewayError.socketFailure
    }
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    let bound = withUnsafePointer(to: &address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.bind(fd, $0, length)
      }
    }
    let flags = Darwin.fcntl(fd, F_GETFL, 0)
    guard bound == 0, flags >= 0,
      Darwin.fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0,
      Darwin.listen(fd, 16) == 0 else {
      Darwin.close(fd)
      throw AppleGatewayError.socketFailure
    }
    var local = sockaddr_in()
    let named = withUnsafeMutablePointer(to: &local) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.getsockname(fd, $0, &length)
      }
    }
    let port = Int(UInt16(bigEndian: local.sin_port))
    guard named == 0, port > 0 else {
      Darwin.close(fd)
      throw AppleGatewayError.socketFailure
    }
    baseURL = "http://127.0.0.1:\(port)"
    listenerFD = fd
    acceptGroup.enter()
    queue.async { self.acceptLoop() }
  }

  var isListening: Bool {
    lock.lock()
    defer { lock.unlock() }
    return !closing && listenerFD >= 0
  }

  func close() {
    lock.lock()
    closing = true
    let active = Array(connections.values)
    lock.unlock()
    for connection in active { connection.cancel() }
  }

  func drain() async {
    await withCheckedContinuation { continuation in
      acceptGroup.notify(queue: queue) {
        self.workers.notify(queue: self.queue) { continuation.resume() }
      }
    }
  }

  deinit { close() }

  private func acceptLoop() {
    lock.lock()
    let ownedFD = listenerFD
    lock.unlock()
    defer {
      lock.lock()
      listenerFD = -1
      lock.unlock()
      Darwin.close(ownedFD)
      acceptGroup.leave()
    }
    while true {
      lock.lock()
      let shouldStop = closing
      lock.unlock()
      if shouldStop { return }
      var watched = pollfd(fd: ownedFD, events: Int16(POLLIN), revents: 0)
      let ready = Darwin.poll(&watched, 1, 250)
      if ready < 0 {
        if errno == EINTR { continue }
        close()
        return
      }
      guard ready > 0 else { continue }
      if watched.revents & Int16(POLLERR | POLLHUP | POLLNVAL) != 0 {
        close()
        return
      }
      guard watched.revents & Int16(POLLIN) != 0 else { continue }
      let client = Darwin.accept(ownedFD, nil, nil)
      if client < 0 {
        if errno == EINTR || errno == EAGAIN { continue }
        close()
        return
      }
      let clientFlags = Darwin.fcntl(client, F_GETFL, 0)
      guard clientFlags >= 0, Darwin.fcntl(client, F_SETFL, clientFlags & ~O_NONBLOCK) == 0 else {
        Darwin.close(client)
        continue
      }
      var noSigPipe: Int32 = 1
      guard Darwin.setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
        Darwin.close(client)
        continue
      }
      let id = UUID()
      let connection = AppleGatewayConnection(localFD: client, node: node, destination: destination) { [weak self] in
        self?.removeConnection(id)
      }
      lock.lock()
      let accepted = !closing && connections.count < 32
      if accepted {
        workers.enter()
        connections[id] = connection
      }
      lock.unlock()
      if accepted {
        queue.async { connection.run() }
      } else {
        connection.cancel()
      }
    }
  }

  private func removeConnection(_ id: UUID) {
    lock.lock()
    let removed = connections.removeValue(forKey: id)
    lock.unlock()
    if removed != nil { workers.leave() }
  }
}

private final class AppleGatewayConnection: @unchecked Sendable {
  private let node: any ApplePrivateNetworkNode
  private let destination: String
  private let onFinish: @Sendable () -> Void
  private let lock = NSLock()
  private var localFD: Int32
  private var upstreamFD: Int32 = -1
  private var cancelled = false

  init(localFD: Int32, node: any ApplePrivateNetworkNode, destination: String, onFinish: @escaping @Sendable () -> Void) {
    self.localFD = localFD
    self.node = node
    self.destination = destination
    self.onFinish = onFinish
  }

  func run() {
    defer { finish() }
    lock.lock()
    let shouldDial = !cancelled
    lock.unlock()
    guard shouldDial else { return }
    let upstream: Int32
    do {
      upstream = try node.dialTCP(destination)
    } catch {
      return
    }
    var noSigPipe: Int32 = 1
    guard Darwin.setsockopt(upstream, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
      Darwin.close(upstream)
      return
    }
    lock.lock()
    guard !cancelled, localFD >= 0 else {
      lock.unlock()
      Darwin.close(upstream)
      return
    }
    upstreamFD = upstream
    let local = localFD
    lock.unlock()

    let pumps = DispatchGroup()
    pumps.enter()
    DispatchQueue.global(qos: .utility).async {
      Self.pump(from: local, to: upstream)
      pumps.leave()
    }
    Self.pump(from: upstream, to: local)
    pumps.wait()
  }

  func cancel() {
    lock.lock()
    cancelled = true
    let local = localFD
    let upstream = upstreamFD
    if local >= 0 {
      Darwin.shutdown(local, SHUT_RDWR)
      if upstream < 0 {
        localFD = -1
        Darwin.close(local)
      }
    }
    if upstream >= 0 { Darwin.shutdown(upstream, SHUT_RDWR) }
    lock.unlock()
  }

  private func finish() {
    lock.lock()
    let local = localFD
    let upstream = upstreamFD
    localFD = -1
    upstreamFD = -1
    cancelled = true
    if local >= 0 { Darwin.close(local) }
    if upstream >= 0 { Darwin.close(upstream) }
    lock.unlock()
    onFinish()
  }

  private static func pump(from source: Int32, to destination: Int32) {
    var buffer = [UInt8](repeating: 0, count: 64 * 1024)
    while true {
      let received = buffer.withUnsafeMutableBytes { Darwin.read(source, $0.baseAddress, $0.count) }
      if received < 0 {
        if errno == EINTR { continue }
        Darwin.shutdown(source, SHUT_RDWR)
        Darwin.shutdown(destination, SHUT_RDWR)
        return
      }
      if received == 0 {
        Darwin.shutdown(destination, SHUT_WR)
        return
      }
      var offset = 0
      while offset < received {
        let written = buffer.withUnsafeBytes {
          Darwin.write(destination, $0.baseAddress!.advanced(by: offset), received - offset)
        }
        if written < 0 && errno == EINTR { continue }
        if written <= 0 {
          Darwin.shutdown(source, SHUT_RDWR)
          Darwin.shutdown(destination, SHUT_RDWR)
          return
        }
        offset += written
      }
    }
  }
}
