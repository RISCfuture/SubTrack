import Foundation

/**
 Given a ``Container``, generates a list of conversion ``Operation``s
 according to the parameters of this instance.
 */
public class Converter {

  /**
   Ordered list of preferred video codecs. Used when ordering and filtering
   video streams.
   */
  public var videoPreferredCodecs = ["av1", "hevc", "h264"]

  /**
   Codec to use when transcoding a video stream whose codec is not in
   ``videoPreferredCodecs``.
   */
  public var videoConversionCodec = "hevc"

  /// Options to use when transcoding a video stream.
  public var videoConversionOptions = ["-preset", "veryslow"]

  /**
   Ordered list of preferred audio codecs. Used when ordering and filtering
   audio streams.
   */
  public var audioPreferredCodecs = ["truehd", "dts", "eac3", "ac3", "flac", "aac"]

  /**
   Codec to use when transcoding an audio stream whose codec is not in
   ``audioPreferredCodecs``.
   */
  public var audioConversionCodec = "eac3"

  /// Options to use when transcoding an audio stream.
  public var audioConversionOptions = [String]()

  /**
   Ordered list of preferred subtitle codecs. Used when ordering and
   filtering subtitle streams.
   */
  public var subtitlePreferredCodecs = ["hdmv_pgs_subtitle", "subrip"]

  /// Subtitle codecs that are incompatible with MKV and need transcoding.
  public var subtitleIncompatibleCodecs = ["mov_text"]

  /// Codec to use when transcoding an incompatible subtitle stream.
  public var subtitleConversionCodec = "srt"

  /// The container file to convert.
  public let container: Container

  /// The audio and subtitle languages to filter in.
  public let languages: [String]

  /**
   If `true`, preserves audio and subtitle tracks with no language
   metadata.
   */
  public var preserveNoLanguages: Bool

  /**
   If `true`, includes audio streams other than the stream with the best
   codec (e.g., commentary tracks or downmixes).
   */
  public var includeOtherAudio: Bool

  private var bestVideoStream: VideoStream? {
    let comparator = VideoComparator(preferredCodecs: videoPreferredCodecs)
    return container.videoStreams.sorted(using: comparator).first
  }

  /**
   The subtitle streams to keep, ordered by the language priority in
   ``languages`` (then by preferred codec within a language), with untagged
   streams last when ``preserveNoLanguages`` is set.
   */
  private var matchingSubtitleStreams: [SubtitleStream] {
    let comparator = SubtitleComparator(preferredCodecs: subtitlePreferredCodecs)
    var streams = languages.flatMap { subtitleStreams(language: $0).sorted(using: comparator) }
    if preserveNoLanguages {
      streams += subtitleStreams(language: nil).sorted(using: comparator)
    }
    return streams
  }

  /**
   Creates an instance.

   - Parameter container: The container file to convert.
   - Parameter languages: The audio and subtitle languages to filter in.
   - Parameter preserveNoLanguages: If `true`, preserves audio and subtitle
   tracks with no language metadata.
   - Parameter includeOtherAudio: If `true`, includes audio streams other than
   the stream with the best codec (e.g., commentary tracks or downmixes).
   */
  public init(
    container: Container,
    languages: [String],
    preserveNoLanguages: Bool = false,
    includeOtherAudio: Bool = false
  ) {
    self.container = container
    self.languages = languages
    self.preserveNoLanguages = preserveNoLanguages
    self.includeOtherAudio = includeOtherAudio
  }

  /**
   A list of operations to perform to convert the media file according to
   the given parameters.
   */
  public func operations() throws -> [StreamOperation] {
    var operations = try [videoOperation()]
    operations += languages.flatMap { audioOperations(language: $0) }
    if preserveNoLanguages { operations += audioOperations(language: nil) }
    operations += subtitleOperations()
    return operations
  }

  private func videoOperation() throws -> StreamOperation {
    guard let bestVideoStream else {
      throw MediaInspectionError.noVideoStream(filename: container.filename)
    }
    return operation(forStream: bestVideoStream)
  }

  /**
   The best default audio stream for `language`, then its other streams when
   ``includeOtherAudio`` is set.
   */
  private func audioOperations(language: String?) -> [StreamOperation] {
    var streams = [AudioStream]()
    if let bestDefault = bestDefaultAudioStream(language: language) { streams.append(bestDefault) }
    if includeOtherAudio { streams += otherAudioStreams(language: language) }
    return streams.map { operation(forStream: $0) }
  }

  private func subtitleOperations() -> [StreamOperation] {
    matchingSubtitleStreams.map { operation(forStream: $0) }
  }

  private func subtitleStreams(language: String?) -> [SubtitleStream] {
    container.subtitleStreams.filter { $0.language == language }
  }

  private func bestDefaultAudioStream(language: String?) -> AudioStream? {
    let comparator = AudioComparator(preferredCodecs: audioPreferredCodecs)
    return container.audioStreams.filter { stream in
      if stream.language != language { return false }
      if !stream.dispositions.isEmpty {
        if !stream.dispositions.contains(.default) && !stream.dispositions.contains(.dub)
          && !stream.dispositions.contains(.original)
        {
          return false
        }
      }
      return true
    }
    .sorted(using: comparator).first
  }

  private func otherAudioStreams(language: String?) -> [AudioStream] {
    let comparator = AudioComparator(preferredCodecs: audioPreferredCodecs)
    return container.audioStreams.filter { stream in
      if stream.language != language { return false }
      if stream.dispositions.isEmpty { return false }
      if stream.dispositions.contains(.default) { return false }
      if stream.dispositions.contains(.dub) { return false }
      if stream.dispositions.contains(.original) { return false }
      return true
    }
    .sorted(using: comparator)
  }

  private func operation(forStream stream: VideoStream) -> StreamOperation {
    if videoPreferredCodecs.contains(stream.codecName) {
      return .init(streamIndex: stream.index, streamType: .video, kind: .copy)
    }
    return .init(
      streamIndex: stream.index,
      streamType: .video,
      kind: .convert(codec: videoConversionCodec, arguments: videoConversionOptions)
    )
  }

  private func operation(forStream stream: AudioStream) -> StreamOperation {
    if audioPreferredCodecs.contains(stream.codecName) {
      return .init(streamIndex: stream.index, streamType: .audio, kind: .copy)
    }
    return .init(
      streamIndex: stream.index,
      streamType: .audio,
      kind: .convert(codec: audioConversionCodec, arguments: audioConversionOptions)
    )
  }

  private func operation(forStream stream: SubtitleStream) -> StreamOperation {
    if subtitleIncompatibleCodecs.contains(stream.codecName) {
      return .init(
        streamIndex: stream.index,
        streamType: .subtitle,
        kind: .convert(codec: subtitleConversionCodec, arguments: [])
      )
    }
    return .init(streamIndex: stream.index, streamType: .subtitle, kind: .copy)
  }
}
