// Compiled with the same ownership source appended to both generated hosts.
private final class FakeNode {
  private(set) var closeCount = 0
  func close() { closeCount += 1 }
}

private actor FakeOwner {
  private var node: FakeNode?
  private var persistedIdentity = false

  func callerOneAcquires() {
    node = FakeNode()
    persistedIdentity = true
  }

  func callerTwoMayBootstrap() -> Bool {
    do {
      _ = try ApplePrivateNetworkBootstrapOwnership(
        hasActiveNode: node != nil,
        hasPersistedIdentity: persistedIdentity
      )
      return true
    } catch {
      return false
    }
  }

  func existingNodeCloseCount() -> Int { node?.closeCount ?? -1 }
  func hasIdentity() -> Bool { persistedIdentity }
}

@main
struct BootstrapOwnershipTests {
  static func main() async throws {
    // A: a later startup failure cleans up only this invocation's node.
    var partial = try ApplePrivateNetworkBootstrapOwnership(
      hasActiveNode: false, hasPersistedIdentity: false)
    let acquired = FakeNode()
    partial.acquiredNode()
    if partial.takeCleanup(activeNode: true) { acquired.close() }
    precondition(acquired.closeCount == 1)
    precondition(partial.takeCleanup(activeNode: true) == false)
    precondition(acquired.closeCount == 1)

    // B: retained identity and a live session reject before ownership.
    do {
      _ = try ApplePrivateNetworkBootstrapOwnership(
        hasActiveNode: true, hasPersistedIdentity: true)
      fatalError("existing node accepted")
    } catch ApplePrivateNetworkBootstrapOwnershipError.nodeAlreadyActive {
    } catch {
      fatalError("wrong existing-node error")
    }
    do {
      _ = try ApplePrivateNetworkBootstrapOwnership(
        hasActiveNode: false, hasPersistedIdentity: true)
      fatalError("existing identity accepted")
    } catch ApplePrivateNetworkBootstrapOwnershipError.existingIdentity {
    } catch {
      fatalError("wrong existing-identity error")
    }

    // C: caller 1 acts before caller 2 enters the serialized transaction.
    let owner = FakeOwner()
    await owner.callerOneAcquires()
    let callerTwoAccepted = await owner.callerTwoMayBootstrap()
    let existingCloseCount = await owner.existingNodeCloseCount()
    let retainedIdentity = await owner.hasIdentity()
    precondition(!callerTwoAccepted)
    precondition(existingCloseCount == 0)
    precondition(retainedIdentity)

    // D: successful completion transfers cleanup to Dart's normal handoff.
    var success = try ApplePrivateNetworkBootstrapOwnership(
      hasActiveNode: false, hasPersistedIdentity: false)
    let successfulNode = FakeNode()
    success.acquiredNode()
    success.completed()
    precondition(!success.takeCleanup(activeNode: true))
    precondition(successfulNode.closeCount == 0)
    successfulNode.close()
    precondition(successfulNode.closeCount == 1)

    // E: failure before acquisition cannot clean up an unrelated node.
    var beforeAcquisition = try ApplePrivateNetworkBootstrapOwnership(
      hasActiveNode: false, hasPersistedIdentity: false)
    precondition(!beforeAcquisition.takeCleanup(activeNode: true))
    print("Apple bootstrap ownership: 5 scenarios passed")
  }
}
