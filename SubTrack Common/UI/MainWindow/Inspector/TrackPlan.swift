import Foundation

/**
 One of a file's tracks paired with what the run will do to it — the unit the
 Override tab lists, describes, and edits.
 */
struct PlannedTrack: Identifiable {
  let stream: any CodedStream
  let type: StreamOperation.StreamType
  let action: TrackAction

  var id: UInt { stream.index }

  /// Whether the run writes this track to the output.
  var isIncluded: Bool { action != .drop }
}

/**
 What a file's run will do to each of its tracks: the selection it will run
 under — its own override when it has one, otherwise the one the queue's
 preset produces — and every managed track in the order the output will carry
 them.

 Within each stream type the kept tracks come first, in the order the run
 writes them (which reflects the rules' language priority), followed by the
 dropped tracks in file order. Video, then audio, then subtitle.
 */
struct TrackPlan {
  let selection: FileTrackSelection
  let tracks: [PlannedTrack]

  init(container: Container, selection: FileTrackSelection?, rules: SlimRules) {
    let resolved = selection ?? Self.seed(container: container, rules: rules)
    self.selection = resolved
    let actions = Dictionary(
      resolved.choices.map { ($0.streamIndex, $0.action) },
      uniquingKeysWith: { first, _ in first }
    )
    let outputOrder = Dictionary(
      resolved.operations().enumerated().map { ($1.streamIndex, $0) },
      uniquingKeysWith: { first, _ in first }
    )
    func ordered(
      _ streams: [some CodedStream],
      _ type: StreamOperation.StreamType
    ) -> [PlannedTrack] {
      Self.order(streams, type: type, actions: actions, outputOrder: outputOrder)
    }
    tracks =
      ordered(container.videoStreams, .video)
      + ordered(container.audioStreams, .audio)
      + ordered(container.subtitleStreams, .subtitle)
  }

  /**
   The selection the queue's preset produces for `container`, used until the
   file has an override of its own. A container the rules can't plan for
   yields an all-dropped selection rather than no tracks at all, so the tab
   still lists what the file holds.
   */
  private static func seed(container: Container, rules: SlimRules) -> FileTrackSelection {
    let operations = (try? rules.makeConverter(container: container).operations()) ?? []
    return FileTrackSelection.seed(container: container, operations: operations)
  }

  private static func order(
    _ streams: [some CodedStream],
    type: StreamOperation.StreamType,
    actions: [UInt: TrackAction],
    outputOrder: [UInt: Int]
  ) -> [PlannedTrack] {
    streams
      .map { PlannedTrack(stream: $0, type: type, action: actions[$0.index] ?? .drop) }
      .sorted { lhs, rhs in
        switch (outputOrder[lhs.id], outputOrder[rhs.id]) {
          case let (left?, right?): left < right
          case (nil, _?): false
          case (_?, nil): true
          case (nil, nil): lhs.id < rhs.id
        }
      }
  }

  /**
   The plan with `action` applied to the track at `index`, ready to be stored
   as the file's own override.
   */
  func setting(_ action: TrackAction, forTrack index: UInt, type: StreamOperation.StreamType)
    -> FileTrackSelection
  {
    var edited = selection
    if let position = edited.choices.firstIndex(where: { $0.streamIndex == index }) {
      edited.choices[position].action = action
    } else {
      edited.choices.append(TrackChoice(streamIndex: index, streamType: type, action: action))
    }
    return edited
  }
}
