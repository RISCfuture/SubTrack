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
 One row of the output as the run will write it: a planned track, where it
 lands in the output, and the flags it comes out carrying — which are not
 always the ones the probe read off the source.
 */
struct OutputTrack: Identifiable {
  let track: PlannedTrack

  /// Its 1-based position in the output, or `nil` when the run drops it.
  let number: Int?

  /// The dispositions the output carries, as distinct from the source's.
  let dispositions: Set<Disposition>

  var id: UInt { track.id }
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

extension TrackPlan {

  /**
   Every track as the output will hold it: numbered in the order the run writes
   them, and carrying the flags the run leaves them with. Dropped tracks are
   still listed, unnumbered, so the plan can be read as a whole.
   */
  var outputTracks: [OutputTrack] {
    let kept = tracks.filter(\.isIncluded)
    let numbers = Dictionary(uniqueKeysWithValues: kept.enumerated().map { ($1.id, $0 + 1) })
    let defaultAudioID = kept.first { $0.type == .audio }?.id
    return tracks.map { track in
      OutputTrack(
        track: track,
        number: numbers[track.id],
        dispositions: outputDispositions(of: track, isDefaultAudio: track.id == defaultAudioID)
      )
    }
  }

  /**
   The flags `track` comes out with: the source's, except that the output's
   first audio track is marked `default` and every other kept audio track has
   that flag taken off it. Mirrors
   ``ProgressReportingProcessor/dispositionArguments(for:)``, which is what
   actually writes them — a plan whose language priority reorders the audio
   must not inherit a `default` from a lower-priority source track.
   */
  private func outputDispositions(of track: PlannedTrack, isDefaultAudio: Bool) -> Set<Disposition>
  {
    let source = track.stream.dispositions
    guard track.isIncluded, track.type == .audio else { return source }
    return isDefaultAudio ? source.union([.default]) : source.subtracting([.default])
  }
}
