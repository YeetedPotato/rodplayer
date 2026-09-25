// The host actor holds its lifecycle gate while using this decision value.
enum ApplePrivateNetworkBootstrapOwnershipError: Error {
  case nodeAlreadyActive
  case existingIdentity
}

struct ApplePrivateNetworkBootstrapOwnership {
  private enum Phase: Equatable {
    case beforeAcquisition
    case acquired
    case completed
  }

  private var phase: Phase = .beforeAcquisition

  init(hasActiveNode: Bool, hasPersistedIdentity: Bool) throws {
    guard !hasActiveNode else {
      throw ApplePrivateNetworkBootstrapOwnershipError.nodeAlreadyActive
    }
    guard !hasPersistedIdentity else {
      throw ApplePrivateNetworkBootstrapOwnershipError.existingIdentity
    }
  }

  mutating func acquiredNode() {
    phase = .acquired
  }

  mutating func completed() {
    phase = .completed
  }

  mutating func takeCleanup(activeNode: Bool) -> Bool {
    guard phase == .acquired && activeNode else { return false }
    phase = .completed
    return true
  }
}
