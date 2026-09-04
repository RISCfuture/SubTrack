public import Foundation

/**
 One queue's own editable settings: its keep-rules (and the preset they came
 from), the format its output is named by, and its output destination. Owned
 by the ``QueueCoordinator`` so every queue keeps — and persists — its own
 settings independently of the others.

 ``onChange`` fires when the keep-rules, active preset, name format, or
 destination change so the owning queue revalidates compatibility, restates
 its output names, and writes the edit through. The inspector routes in-place
 edits through ``editRules(_:)`` and ``editNaming(_:)`` so every settings edit
 flows through this one hook rather than a view-level observer that also fires
 when the selection switches to a queue with different rules.
 */
@MainActor
@Observable
public final class QueueSettings {
  /// The queue's keep-rules and the preset they came from.
  public let rules: RulesModel

  /// How the queue names the files it produces.
  public private(set) var naming: OutputNameFormat

  /// Where the queue writes its slimmed output.
  public let destination: QueueDestination

  /// Fired when the active preset, name format, or destination changes.
  public var onChange: @MainActor () -> Void = {}

  /// Creates settings from persisted or seeded values.
  public init(
    rules: SlimRules = .default,
    naming: OutputNameFormat = .slimmed,
    activePresetID: UUID? = nil,
    destinationBookmark: Data? = nil
  ) {
    let rulesModel = RulesModel(rules: rules)
    rulesModel.activePresetID = activePresetID
    self.rules = rulesModel
    self.naming = naming
    self.destination = QueueDestination(bookmark: destinationBookmark)
    destination.onChange = { [weak self] in self?.onChange() }
  }

  /**
   Applies `preset`'s rules and name format to the queue and notifies the
   owning queue.
   */
  public func apply(_ preset: Preset) {
    rules.apply(preset)
    naming = preset.naming
    onChange()
  }

  /**
   Replaces the queue's output-name format and notifies the owning queue, so
   the edit restates every pending item's output path and persists.
   */
  public func editNaming(_ naming: OutputNameFormat) {
    guard naming != self.naming else { return }
    self.naming = naming
    onChange()
  }

  /**
   Mutates the queue's keep-rules in place and notifies the owning queue, so a
   rules-field edit revalidates compatibility and persists through the same
   hook as a preset or destination change.
   */
  public func editRules(_ mutate: (inout SlimRules) -> Void) {
    mutate(&rules.rules)
    onChange()
  }

  /**
   Overwrites the queue's settings from a persisted `snapshot` at hydration.
   Does not fire ``onChange``.
   */
  public func hydrate(_ snapshot: QueueSnapshot) {
    rules.rules = snapshot.rules
    rules.activePresetID = snapshot.activePresetID
    naming = snapshot.naming
    destination.load(snapshot.destinationBookmark)
  }
}
