import Foundation

/// What to do with a single detected track when building a per-file override.
public enum TrackAction: Codable, Sendable, Equatable {

  /// Keep the track, stream-copied.
  case copy

  /// Keep the track, transcoded to `codec` with the given options.
  case convert(codec: String, options: [String])

  /// Remove the track from the output.
  case drop
}

/**
 A transcode target offered by the per-track “Convert to…” picker: an
 `ffmpeg` `-c:x` value paired with a human-readable label.
 */
public struct ConversionTarget: Sendable, Equatable, Identifiable {

  /**
   The `ffmpeg` `-c:x` value — an encoder name (e.g. `hevc_videotoolbox`) or
   a codec name (e.g. `hevc`) that resolves to that codec's default encoder.
   */
  public let codec: String

  /**
   The label shown for the target once it is chosen, kept short enough to sit
   in a collapsed menu.
   */
  public let displayName: String

  /**
   What the encoder is, as `ffmpeg` itself describes it — shown alongside
   ``displayName`` in the open menu, where there is room to explain. Empty for
   the built-in catalog entries, whose display names already read plainly.
   */
  public let summary: String

  public var id: String { codec }

  public init(codec: String, displayName: String, summary: String = "") {
    self.codec = codec
    self.displayName = displayName
    self.summary = summary
  }
}

/// A per-track choice in a per-file override.
public struct TrackChoice: Codable, Sendable, Equatable, Identifiable {
  public var id: UInt { streamIndex }

  /// The track's index within its source container.
  public let streamIndex: UInt

  /// Which of the container's track lists the track came from.
  public let streamType: StreamOperation.StreamType

  /// What the override does with the track.
  public var action: TrackAction

  /**
   Creates a choice.

   - Parameter streamIndex: The track's index within its source container.
   - Parameter streamType: Which of the container's track lists the track came
     from.
   - Parameter action: What the override does with the track.
   */
  public init(streamIndex: UInt, streamType: StreamOperation.StreamType, action: TrackAction) {
    self.streamIndex = streamIndex
    self.streamType = streamType
    self.action = action
  }
}

/**
 An explicit, per-file selection of tracks that overrides the global rules.
 The inspector edits this; the engine turns it into ``Operation``s.
 */
public struct FileTrackSelection: Codable, Sendable, Equatable {
  public var choices: [TrackChoice]

  public init(choices: [TrackChoice]) {
    self.choices = choices
  }

  /**
   Seeds a selection showing *every* coded track in `container`, preselecting
   each track's action from the rule-derived `operations` (tracks the rules
   would drop start as ``TrackAction/drop``). This is what the per-file
   inspector presents so the user can toggle from the rule outcome.

   Within each stream type, kept tracks come first in `operations` order —
   which reflects the rules' language priority and therefore the output track
   order — followed by the dropped tracks in file order. Video, then audio,
   then subtitle, matching the sectioned inspector.
   */
  public static func seed(container: Container, operations: [StreamOperation]) -> Self {
    let actionsByIndex = Dictionary(
      operations.map { ($0.streamIndex, action(for: $0.kind)) },
      uniquingKeysWith: { first, _ in first }
    )
    let keptOrder = Dictionary(
      operations.enumerated().map { ($1.streamIndex, $0) },
      uniquingKeysWith: { first, _ in first }
    )

    func choices(for streams: [some Stream], type: StreamOperation.StreamType) -> [TrackChoice] {
      streams
        .map {
          TrackChoice(
            streamIndex: $0.index,
            streamType: type,
            action: actionsByIndex[$0.index] ?? .drop
          )
        }
        .sorted { lhs, rhs in
          switch (keptOrder[lhs.streamIndex], keptOrder[rhs.streamIndex]) {
            case let (left?, right?): return left < right
            case (nil, _?): return false
            case (_?, nil): return true
            case (nil, nil): return lhs.streamIndex < rhs.streamIndex
          }
        }
    }

    var allChoices = [TrackChoice]()
    allChoices += choices(for: container.videoStreams, type: .video)
    allChoices += choices(for: container.audioStreams, type: .audio)
    allChoices += choices(for: container.subtitleStreams, type: .subtitle)
    return Self(choices: allChoices)
  }

  private static func action(for kind: StreamOperation.Kind) -> TrackAction {
    switch kind {
      case .copy: .copy
      case let .convert(codec, arguments): .convert(codec: codec, options: arguments)
    }
  }

  /// The kept tracks as `ffmpeg` ``StreamOperation``s (dropped tracks are omitted).
  public func operations() -> [StreamOperation] {
    choices.compactMap { choice in
      switch choice.action {
        case .drop:
          return nil
        case .copy:
          return StreamOperation(
            streamIndex: choice.streamIndex,
            streamType: choice.streamType,
            kind: .copy
          )
        case let .convert(codec, options):
          return StreamOperation(
            streamIndex: choice.streamIndex,
            streamType: choice.streamType,
            kind: .convert(codec: codec, arguments: options)
          )
      }
    }
  }
}

extension FileTrackSelection {

  // Video targets use explicit encoder names, not codec families: `libx265`
  // resolves only against a build that actually ships x265, so it's correctly
  // hidden on a VideoToolbox-only (LGPL) build — whereas the family name `hevc`
  // is aliased onto `hevc_videotoolbox` and would mislabel VideoToolbox as x265.
  private static let videoTargetCatalog = [
    ConversionTarget(codec: "libx265", displayName: String(localized: "HEVC (x265)")),
    ConversionTarget(codec: "libx264", displayName: String(localized: "H.264 (x264)")),
    ConversionTarget(
      codec: "hevc_videotoolbox",
      displayName: String(localized: "HEVC (VideoToolbox)")
    ),
    ConversionTarget(
      codec: "h264_videotoolbox",
      displayName: String(localized: "H.264 (VideoToolbox)")
    )
  ]

  private static let audioTargetCatalog = [
    ConversionTarget(codec: "aac", displayName: String(localized: "AAC")),
    ConversionTarget(codec: "ac3", displayName: String(localized: "AC-3")),
    ConversionTarget(codec: "eac3", displayName: String(localized: "E-AC-3")),
    ConversionTarget(codec: "flac", displayName: String(localized: "FLAC")),
    ConversionTarget(codec: "alac", displayName: String(localized: "ALAC")),
    ConversionTarget(codec: "libopus", displayName: String(localized: "Opus")),
    ConversionTarget(codec: "truehd", displayName: String(localized: "TrueHD")),
    ConversionTarget(codec: "dts", displayName: String(localized: "DTS"))
  ]

  private static let subtitleTargetCatalog = [
    ConversionTarget(codec: "srt", displayName: String(localized: "SubRip (SRT)")),
    ConversionTarget(codec: "ass", displayName: String(localized: "Advanced SubStation (ASS)")),
    ConversionTarget(codec: "mov_text", displayName: String(localized: "MP4 Timed Text"))
  ]

  /**
   Everything the probed build can write for `streamType` — the codec families
   it can produce, then every individual encoder — named and described as
   `ffmpeg` names and describes them.

   Families come first because they are the portable choice: `hevc` resolves
   to whichever HEVC encoder the build prefers, where `hevc_videotoolbox`
   commits to one. Both are valid `-c:x` values, so both are offered.

   Preferred over the ``availableTargets(for:capabilities:)`` catalog wherever
   a probe has landed: it is the resolved binary's own answer rather than a
   curated guess, so a build's extra encoders are offered and its missing ones
   never are.
   */
  public static func availableTargets(
    for streamType: StreamOperation.StreamType,
    capabilities: FFmpegCapabilities
  ) -> [ConversionTarget] {
    let codecs =
      switch streamType {
        case .video: capabilities.videoCodecs
        case .audio: capabilities.audioCodecs
        case .subtitle: capabilities.subtitleCodecs
      }
    let encoders = codecs.filter(\.canEncode)
    let described = Dictionary(
      codecs.map { ($0.name, $0) },
      uniquingKeysWith: { first, _ in first }
    )

    // A family that is also an encoder's own name is already in the list below.
    let families = Set(encoders.compactMap(\.family))
      .subtracting(encoders.map(\.name))
      .sorted()

    return families.map { family in
      ConversionTarget(
        codec: family,
        displayName: family,
        summary: described[family].map(describe) ?? ""
      )
    }
      + encoders.map {
        ConversionTarget(codec: $0.name, displayName: $0.name, summary: describe($0))
      }
  }

  /**
   A short catalog of the transcode targets worth offering before a build has
   been probed, filtered by what its `capabilities` say it can encode.
   VideoToolbox-only builds omit the software (x264/x265) and other GPL
   encoders they cannot run; subtitle targets don't depend on `capabilities`.
   */
  public static func availableTargets(
    for streamType: StreamOperation.StreamType,
    capabilities: EncoderCapabilities
  ) -> [ConversionTarget] {
    switch streamType {
      case .video: videoTargetCatalog.filter { capabilities.supportsVideo($0.codec) }
      case .audio: audioTargetCatalog.filter { capabilities.supportsAudio($0.codec) }
      case .subtitle: subtitleTargetCatalog
    }
  }

  /**
   An encoder's description, trimmed of what the target already says for
   itself: `ffmpeg` writes `libx264 H.264 / AVC / … (codec h264)`, where the
   leading name is the target's own display name and the trailing family is
   listed as a target in its own right.
   */
  private static func describe(_ codec: FFmpegCodec) -> String {
    var summary = Substring(codec.summary)
    if summary.hasPrefix("\(codec.name) ") { summary = summary.dropFirst(codec.name.count + 1) }
    if let family = codec.family, summary.hasSuffix("(codec \(family))") {
      summary = summary.dropLast("(codec \(family))".count)
    }
    return summary.trimmingCharacters(in: .whitespaces)
  }
}
