import Foundation

/**
 A `Codable`, `Sendable` capture of every track-selection preference the
 engine understands — the value type behind the UI's global keep-rules and a
 saved ``Preset``. Applies itself to a ``Converter`` via ``makeConverter(container:)``.
 */
public struct SlimRules: Codable, Sendable, Equatable {

  /// The engine's default rules (matching the CLI defaults).
  public static let `default` = Self()

  /// The x264/x265 speed presets, which name a `-preset` and never a profile.
  private static let encoderPresetNames: Set<String> = [
    "ultrafast", "superfast", "veryfast", "faster", "fast",
    "medium", "slow", "slower", "veryslow", "placebo"
  ]

  /**
   The video preferred-codec list that omits `av1`.
   `repairedPreferredCodecs(_:)` adds `av1` to a stored list matching it
   exactly.
   */
  private static let preAV1PreferredCodecs = ["hevc", "h264"]

  /**
   Audio encoders FFmpeg marks experimental, which refuse to open without
   `-strict -2`. Naming one as the transcode target fails every run that
   needs it, so ``repairedConversionCodec(_:)`` swaps it out.
   */
  private static let experimentalAudioEncoders: Set<String> = ["truehd", "dts", "dca"]

  /**
   The transcode target for audio the preferred list doesn't cover: Dolby
   Digital Plus, the best-supported home-cinema codec FFmpeg can actually
   encode once the lossless ones are ruled out.
   */
  private static let usableAudioConversionCodec = "eac3"

  /// The audio and subtitle languages (ISO 639-2) to keep.
  public var languages: [String]

  /// Whether to keep audio/subtitle tracks that have no language metadata.
  public var preserveNoLanguages: Bool

  /// Whether to keep non-default audio (commentary, downmixes, etc.) and the
  /// subtitles flagged as commentary.
  public var includeOtherAudio: Bool

  /// Preferred video codecs, in priority order.
  public var videoPreferredCodecs: [String]

  /// Encoder used when transcoding a non-preferred video stream.
  public var videoConversionCodec: String

  /// Extra `ffmpeg` options applied when transcoding video.
  public var videoConversionOptions: [String]

  /// Preferred audio codecs, in priority order.
  public var audioPreferredCodecs: [String]

  /// Encoder used when transcoding a non-preferred audio stream.
  public var audioConversionCodec: String

  /// Extra `ffmpeg` options applied when transcoding audio.
  public var audioConversionOptions: [String]

  /// Preferred subtitle codecs, in priority order.
  public var subtitlePreferredCodecs: [String]

  public init(
    languages: [String] = ["eng"],
    preserveNoLanguages: Bool = false,
    includeOtherAudio: Bool = false,
    videoPreferredCodecs: [String] = ["av1", "hevc", "h264"],
    videoConversionCodec: String = "hevc",
    videoConversionOptions: [String] = ["-preset", "veryslow"],
    audioPreferredCodecs: [String] = ["truehd", "dts", "eac3", "ac3", "flac", "aac"],
    audioConversionCodec: String = "eac3",
    audioConversionOptions: [String] = [],
    subtitlePreferredCodecs: [String] = ["hdmv_pgs_subtitle", "subrip"]
  ) {
    self.languages = languages
    self.preserveNoLanguages = preserveNoLanguages
    self.includeOtherAudio = includeOtherAudio
    self.videoPreferredCodecs = videoPreferredCodecs
    self.videoConversionCodec = videoConversionCodec
    self.videoConversionOptions = videoConversionOptions
    self.audioPreferredCodecs = audioPreferredCodecs
    self.audioConversionCodec = audioConversionCodec
    self.audioConversionOptions = audioConversionOptions
    self.subtitlePreferredCodecs = subtitlePreferredCodecs
  }

  /**
   Decodes rules written by any earlier build.

   Every field falls back to its default when the stored blob lacks it, so a
   record written before a field existed keeps the rest of its values instead of
   reverting wholesale — synthesized `Codable` would throw `keyNotFound` and the
   callers' `try?` would swallow the whole record.

   Two stored values are also corrected on the way in; see
   `repairedConversionOptions(_:)` and `repairedPreferredCodecs(_:)`.
   */
  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    let defaults = Self()

    languages =
      try values.decodeIfPresent([String].self, forKey: .languages) ?? defaults.languages
    preserveNoLanguages =
      try values.decodeIfPresent(Bool.self, forKey: .preserveNoLanguages)
      ?? defaults.preserveNoLanguages
    includeOtherAudio =
      try values.decodeIfPresent(Bool.self, forKey: .includeOtherAudio)
      ?? defaults.includeOtherAudio
    videoPreferredCodecs = Self.repairedPreferredCodecs(
      try values.decodeIfPresent([String].self, forKey: .videoPreferredCodecs)
        ?? defaults.videoPreferredCodecs
    )
    videoConversionCodec =
      try values.decodeIfPresent(String.self, forKey: .videoConversionCodec)
      ?? defaults.videoConversionCodec
    videoConversionOptions = Self.repairedConversionOptions(
      try values.decodeIfPresent([String].self, forKey: .videoConversionOptions)
        ?? defaults.videoConversionOptions
    )
    audioPreferredCodecs =
      try values.decodeIfPresent([String].self, forKey: .audioPreferredCodecs)
      ?? defaults.audioPreferredCodecs
    audioConversionCodec = Self.repairedConversionCodec(
      try values.decodeIfPresent(String.self, forKey: .audioConversionCodec)
        ?? defaults.audioConversionCodec
    )
    audioConversionOptions =
      try values.decodeIfPresent([String].self, forKey: .audioConversionOptions)
      ?? defaults.audioConversionOptions
    subtitlePreferredCodecs =
      try values.decodeIfPresent([String].self, forKey: .subtitlePreferredCodecs)
      ?? defaults.subtitlePreferredCodecs
  }

  /**
   Rewrites `-profile:v <speed preset>` to `-preset <speed preset>`.

   A speed preset names no encoder profile, so ffmpeg refuses to open the
   encoder and the run fails outright. Nobody could have chosen the pairing
   deliberately, which makes correcting it in place safe. A genuine profile
   such as `main10` is left alone.
   */
  private static func repairedConversionOptions(_ options: [String]) -> [String] {
    var repaired = options
    for flag in options.indices where options[flag] == "-profile:v" {
      let value = options.index(after: flag)
      guard options.indices.contains(value), encoderPresetNames.contains(options[value]) else {
        continue
      }
      repaired[flag] = "-preset"
    }
    return repaired
  }

  /**
   Replaces an experimental audio transcode target with one FFmpeg will
   actually open.

   FFmpeg's `truehd` and `dts` encoders are experimental and refuse to open
   without `-strict -2`, so naming either as the transcode target fails the run
   outright with "experimental codecs are not enabled". A target already
   pointing at a usable encoder is left alone.
   */
  private static func repairedConversionCodec(_ codec: String) -> String {
    experimentalAudioEncoders.contains(codec) ? usableAudioConversionCodec : codec
  }

  /**
   Adds `av1` to a stored preferred-codec list that exactly matches
   ``preAV1PreferredCodecs``, so AV1 sources are copied rather than transcoded.
   Any other list is the user's own choice and is left as it is.
   */
  private static func repairedPreferredCodecs(_ codecs: [String]) -> [String] {
    codecs == preAV1PreferredCodecs ? ["av1"] + preAV1PreferredCodecs : codecs
  }

  /// Builds a configured ``Converter`` for a container from these rules.
  public func makeConverter(container: Container) -> Converter {
    let converter = Converter(
      container: container,
      languages: languages,
      preserveNoLanguages: preserveNoLanguages,
      includeOtherAudio: includeOtherAudio
    )
    converter.videoPreferredCodecs = videoPreferredCodecs
    converter.videoConversionCodec = videoConversionCodec
    converter.videoConversionOptions = videoConversionOptions
    converter.audioPreferredCodecs = audioPreferredCodecs
    converter.audioConversionCodec = audioConversionCodec
    converter.audioConversionOptions = audioConversionOptions
    converter.subtitlePreferredCodecs = subtitlePreferredCodecs
    return converter
  }
}
