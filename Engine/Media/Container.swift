import Foundation

/// A video, audio, or subtitle stream.
public protocol Stream: Decodable, Sendable {

  /// The stream index.
  var index: UInt { get }

  /// The stream dispositions.
  var dispositions: Set<Disposition> { get }

  /// The stream tags.
  var tags: [String: String] { get }
}

/// A stream with an associated codec.
protocol CodedStream: Stream {

  /// The codec name.
  var codecName: String { get }

  /**
   The number of packets read from the stream, if `ffprobe` was invoked
   with `-count_packets` (see ``Reader/open(file:countPackets:)``).
   `nil` otherwise or if the count could not be determined.
   */
  var nbReadPackets: UInt? { get }
}

extension Stream {

  /// The stream's language in ISO 639-2 format (applies to audio and subtitle stream).
  public var language: String? { tags["language"] }

  /// The stream bit density (bits per second), if provided.
  public var bitsPerSecond: UInt? { tags["BPS"] != nil ? UInt(tags["BPS"]!) : nil }

  /// The stream title, if provided.
  public var title: String? { tags["title"] }

  static func decodeDispositions(_ dispositions: [String: UInt8]) -> Set<Disposition> {
    var set = Set<Disposition>()
    for (key, value) in dispositions {
      guard value == 1 else { continue }
      guard let disposition = Disposition(rawValue: key) else { continue }
      set.insert(disposition)
    }
    return set
  }
}

/// A stream with video data.
public struct VideoStream: CodedStream {
  public let index: UInt
  public let codecName: String
  public let dispositions: Set<Disposition>
  public let tags: [String: String]
  public let nbReadPackets: UInt?

  /// The video encoding profile (e.g., `high`).
  public let profile: String?

  /// The video width, in pixels.
  public let width: UInt

  /// The video height, in pixels.
  public let height: UInt

  /**
   The video pixel format tag (e.g., YUV420), if known. May be absent
   for degenerate streams (e.g., an output container with a declared
   but empty video stream).
   */
  public let pixelFormat: String?

  /// The temporal resolution (interlaced or progressive), if specified.
  public let fieldOrder: FieldOrder?

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let type = try container.decode(String.self, forKey: .codec_type)
    guard type == "video" else { throw MediaInspectionError.unknownStreamType(type) }

    index = try container.decode(UInt.self, forKey: .index)
    codecName = try container.decode(String.self, forKey: .codec_name)
    profile = try container.decodeIfPresent(String.self, forKey: .profile)
    width = try container.decode(UInt.self, forKey: .width)
    height = try container.decode(UInt.self, forKey: .height)
    pixelFormat = try container.decodeIfPresent(String.self, forKey: .pix_fmt)
    fieldOrder = try container.decodeIfPresent(FieldOrder.self, forKey: .field_order)
    tags = try container.decodeIfPresent(Dictionary<String, String>.self, forKey: .tags) ?? [:]
    nbReadPackets = try container.decodeIfPresent(String.self, forKey: .nb_read_packets)
      .flatMap { UInt($0) }

    let dispositions = try container.decode(Dictionary<String, UInt8>.self, forKey: .disposition)
    self.dispositions = Self.decodeDispositions(dispositions)
  }

  private enum CodingKeys: String, CodingKey {
    case index, codec_name, profile, width, height, pix_fmt, field_order, tags, disposition,
      codec_type, nb_read_packets
  }

  /// Video field orders.
  public enum FieldOrder: String, Decodable, Sendable {

    /// Progressive video: full temporal resolution.
    case progressive

    /// Interlaced video, top field coded and displayed first
    case tt

    /// Interlaced video, bottom field coded and displayed first
    case bb

    /// Interlaced video, top coded first, bottom displayed first
    case tb

    /// Interlaced video, bottom coded first, top displayed first
    case bt
  }
}

/// An stream with audio data.
public struct AudioStream: CodedStream {
  public let index: UInt
  public let codecName: String
  public let dispositions: Set<Disposition>
  public let tags: [String: String]
  public let nbReadPackets: UInt?

  /// The audio encoding profile (e.g., `high`).
  public let profile: String?

  /// The audio sample format (e.g., AAC HE v2).
  public let sampleFormat: String?

  /// The audio sample rate, in hertz (e.g., 44100 for 44 kHz).
  public let sampleRate: UInt

  /// The number of bits per sample (e.g., 24-bit audio).
  public let bitsPerSample: UInt

  /// The number of audio channels (e.g., 2 for stereo).
  public let channelCount: UInt

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let type = try container.decode(String.self, forKey: .codec_type)
    guard type == "audio" else { throw MediaInspectionError.unknownStreamType(type) }

    index = try container.decode(UInt.self, forKey: .index)
    codecName = try container.decode(String.self, forKey: .codec_name)
    profile = try container.decodeIfPresent(String.self, forKey: .profile)
    sampleFormat = try container.decodeIfPresent(String.self, forKey: .sample_fmt)
    let sampleRateString = try container.decode(String.self, forKey: .sample_rate)
    guard let sampleRate = UInt(sampleRateString) else {
      throw MediaInspectionError.malformedMetadata(field: "sample_rate")
    }
    self.sampleRate = sampleRate
    channelCount = try container.decode(UInt.self, forKey: .channels)
    var bitsPerSample = try container.decode(UInt.self, forKey: .bits_per_sample)
    if bitsPerSample == 0,
      let bitsPerRawSampleString = try container.decodeIfPresent(
        String.self,
        forKey: .bits_per_raw_sample
      ),
      let bitsPerRawSample = UInt(bitsPerRawSampleString)
    {
      bitsPerSample = bitsPerRawSample
    }
    self.bitsPerSample = bitsPerSample
    tags = try container.decodeIfPresent(Dictionary<String, String>.self, forKey: .tags) ?? [:]
    nbReadPackets = try container.decodeIfPresent(String.self, forKey: .nb_read_packets)
      .flatMap { UInt($0) }

    let dispositions = try container.decode(Dictionary<String, UInt8>.self, forKey: .disposition)
    self.dispositions = Self.decodeDispositions(dispositions)
  }

  private enum CodingKeys: String, CodingKey {
    case index, codec_name, profile, sample_fmt, sample_rate, channels, bits_per_sample, tags,
      disposition, codec_type, bits_per_raw_sample, nb_read_packets
  }
}

/// A stream with subtitle data.
public struct SubtitleStream: CodedStream {
  public let index: UInt
  public let codecName: String
  public let nbReadPackets: UInt?

  public let dispositions: Set<Disposition>
  public let tags: [String: String]

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let type = try container.decode(String.self, forKey: .codec_type)
    guard type == "subtitle" else { throw MediaInspectionError.unknownStreamType(type) }

    index = try container.decode(UInt.self, forKey: .index)
    codecName = try container.decode(String.self, forKey: .codec_name)
    tags = try container.decodeIfPresent(Dictionary<String, String>.self, forKey: .tags) ?? [:]
    nbReadPackets = try container.decodeIfPresent(String.self, forKey: .nb_read_packets)
      .flatMap { UInt($0) }

    let dispositions = try container.decode(Dictionary<String, UInt8>.self, forKey: .disposition)
    self.dispositions = Self.decodeDispositions(dispositions)
  }

  private enum CodingKeys: String, CodingKey {
    case index, codec_name, tags, disposition, codec_type, nb_read_packets
  }
}

/// A stream with attached file data.
struct AttachmentStream: Stream {
  let index: UInt

  let dispositions: Set<Disposition>
  let tags: [String: String]

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let type = try container.decode(String.self, forKey: .codec_type)
    guard type == "attachment" else { throw MediaInspectionError.unknownStreamType(type) }

    index = try container.decode(UInt.self, forKey: .index)
    tags = try container.decodeIfPresent(Dictionary<String, String>.self, forKey: .tags) ?? [:]

    let dispositions = try container.decode(Dictionary<String, UInt8>.self, forKey: .disposition)
    self.dispositions = Self.decodeDispositions(dispositions)
  }

  private enum CodingKeys: String, CodingKey {
    case index, tags, disposition, codec_type
  }
}

/// A stream with arbitrary data (ignored during conversion).
struct DataStream: Stream {
  let index: UInt

  let dispositions: Set<Disposition>
  let tags: [String: String]

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let type = try container.decode(String.self, forKey: .codec_type)
    guard type == "data" else { throw MediaInspectionError.unknownStreamType(type) }

    index = try container.decode(UInt.self, forKey: .index)
    tags = try container.decodeIfPresent(Dictionary<String, String>.self, forKey: .tags) ?? [:]

    let dispositions = try container.decode(Dictionary<String, UInt8>.self, forKey: .disposition)
    self.dispositions = Self.decodeDispositions(dispositions)
  }

  private enum CodingKeys: String, CodingKey {
    case index, tags, disposition, codec_type
  }
}

/// Stream dispositions provide usage hints for a stream.
public enum Disposition: String, Decodable, Sendable {

  /// Default disposition
  case `default`

  /// Dubbed audio
  case dub

  /// Original audio
  case original

  /// Commentary audio or subtitles
  case comment

  /// Musical lyrics subtitles
  case lyrics

  /// Karaoke audio (without lead singer)
  case karaoke

  /// Forced subtitle track (displayed even when subtitles are turned off)
  case forced

  /// Subtitles for hearing impaired viewers
  case hearingImpaired = "hearing_impaired"

  /// Audio for visually impaired viewers
  case visualImpaired = "visual_impaired"

  /// Audio with clean effects
  case cleanEffects = "clean_effects"

  /// Attachment with thumbnail or cover image
  case attachedPic = "attached_pic"

  /// Attachment with timed thumbnails
  case timedThumbnails = "timed_thumbnails"

  /// Audio track without music or narration
  case nonDiegetic = "non_diegetic"

  /// Attachment with thumbnail captions
  case captions

  /// Attachment with description text
  case descriptions

  /// Attachment with metadata information
  case metadata

  /// Track dependent on another track
  case dependent

  /// Attachment with still image
  case stillImage = "still_image"

  /// Multilayer track
  case multilayer
}

/// A container file contains one or more ``Stream``s.
public struct Container: Decodable, Sendable {

  private static let bitsPerByte = 8.0

  /// The name of the container file.
  public let filename: String

  /// The media duration, in seconds.
  public let durationSec: Double

  /// The media size, in bytes.
  public let size: UInt

  /// The container tags.
  public let tags: [String: String]

  /// The streams in the container.
  public let streams: [Stream]

  /// The video streams.
  public var videoStreams: [VideoStream] { streams.compactMap { $0 as? VideoStream } }

  /// The audio streams.
  public var audioStreams: [AudioStream] { streams.compactMap { $0 as? AudioStream } }

  /// The subtitle streams.
  public var subtitleStreams: [SubtitleStream] { streams.compactMap { $0 as? SubtitleStream } }

  /**
   The video, audio, and subtitle streams, in file order — the ones a
   conversion chooses between. Attachments and data streams are excluded.
   */
  public var managedStreams: [any Stream] {
    streams.filter { $0 is VideoStream || $0 is AudioStream || $0 is SubtitleStream }
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    var codedStreams = try container.nestedUnkeyedContainer(forKey: .streams)
    var decodedStreams = [Stream]()
    while !codedStreams.isAtEnd {
      if let stream = try Self.decodeStream(from: &codedStreams) { decodedStreams.append(stream) }
    }
    streams = decodedStreams

    let format = try container.nestedContainer(keyedBy: FormatCodingKeys.self, forKey: .format)
    filename = try format.decode(String.self, forKey: .filename)
    durationSec = try Self.decodeNumber(Double.self, from: format, forKey: .duration)
    size = try Self.decodeNumber(UInt.self, from: format, forKey: .size)
    tags = try format.decodeIfPresent(Dictionary<String, String>.self, forKey: .tags) ?? [:]
  }

  /**
   Decodes the next stream by trying each known stream type in turn: every
   concrete type throws ``MediaInspectionError/unknownStreamType(_:)`` when the
   row's `codec_type` isn't its own, so the first that doesn't throw is the
   right one. Returns `nil` for data streams, which a conversion never touches.
   */
  private static func decodeStream(
    from codedStreams: inout UnkeyedDecodingContainer
  ) throws -> (any Stream)? {
    let candidates: [(inout UnkeyedDecodingContainer) throws -> any Stream] = [
      { try $0.decode(VideoStream.self) },
      { try $0.decode(AudioStream.self) },
      { try $0.decode(SubtitleStream.self) },
      { try $0.decode(AttachmentStream.self) }
    ]
    for decode in candidates {
      do {
        return try decode(&codedStreams)
      } catch MediaInspectionError.unknownStreamType {
        continue
      }
    }
    _ = try codedStreams.decode(DataStream.self)
    return nil
  }

  /**
   Decodes a numeric `ffprobe` field, which the wire format quotes as a string.

   - Throws: ``MediaInspectionError/malformedMetadata(field:)`` when the string
     doesn't parse as the requested type.
   */
  private static func decodeNumber<Value: LosslessStringConvertible>(
    _: Value.Type,
    from format: KeyedDecodingContainer<FormatCodingKeys>,
    forKey key: FormatCodingKeys
  ) throws -> Value {
    guard let value = Value(try format.decode(String.self, forKey: key)) else {
      throw MediaInspectionError.malformedMetadata(field: key.rawValue)
    }
    return value
  }

  /**
   The combined size, in bytes, of the managed streams whose indices aren't in
   `keptIndices` — what dropping them would reclaim, derived from each
   stream's declared bit rate over the container's duration.

   `nil` when any dropped stream declares no bit rate, since summing only the
   ones that do would understate the total by an unknowable amount.
   */
  public func byteCount(ofStreamsExcluding keptIndices: Set<UInt>) -> Int? {
    let dropped = managedStreams.filter { !keptIndices.contains($0.index) }
    let bitRates = dropped.compactMap(\.bitsPerSecond)
    guard bitRates.count == dropped.count else { return nil }
    return bitRates.reduce(0) { $0 + Int(Double($1) * durationSec / Self.bitsPerByte) }
  }

  private enum CodingKeys: String, CodingKey {
    case format
    case streams
  }

  private enum FormatCodingKeys: String, CodingKey {
    case filename, duration, size, tags
  }
}
