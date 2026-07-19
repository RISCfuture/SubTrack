import Foundation

/**
 The persisted, settled subset of ``QueueItemState``. Transient states
 (`waiting`/`probing`/`running`) are not stored: a queue restores idle, so an
 in-flight item collapses to ``ready``. The reason string carried by the live
 `failed`/`incompatible` states is stored separately (in the item's
 `lastError`), keeping this enum a plain `String`-backed value.
 */
public enum PersistedItemStatus: String, Codable, Sendable, CaseIterable {
  case ready
  case done
  case failed
  case cancelled
  case missing
  case incompatible
}

extension PersistedItemStatus {

  /**
   The persisted status for a live queue-item `state`. Transient states
   collapse to ``ready``; the reason carried by `failed`/`incompatible` is not
   captured here — read ``QueueItemState/persistedReason`` for that.
   */
  public init(_ state: QueueItemState) {
    switch state {
      case .waiting, .probing, .ready, .running: self = .ready
      case .done: self = .done
      case .cancelled: self = .cancelled
      case .missing: self = .missing
      case .failed: self = .failed
      case .incompatible: self = .incompatible
    }
  }

  /**
   The live queue-item state to hydrate this persisted status into, using
   `reason` for the `failed`/`incompatible` cases that carry one.
   */
  public func state(reason: String? = nil) -> QueueItemState {
    switch self {
      case .ready: .ready
      case .done: .done
      case .cancelled: .cancelled
      case .missing: .missing
      case .failed: .failed(reason ?? "")
      case .incompatible: .incompatible(reason ?? "")
    }
  }
}

extension QueueItemState {

  /**
   The human-readable reason carried by `failed`/`incompatible`, else `nil`.
   Persisted alongside ``PersistedItemStatus`` so the state round-trips.
   */
  public var persistedReason: String? {
    switch self {
      case let .failed(reason), let .incompatible(reason): reason
      default: nil
    }
  }
}
