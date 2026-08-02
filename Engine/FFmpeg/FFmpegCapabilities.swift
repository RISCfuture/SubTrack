import Foundation

/**
 The kind of stream a codec applies to, as reported by `ffmpeg -encoders`
 / `-decoders`.
 */
public enum FFmpegMediaType: String, Sendable, CaseIterable {
  case video
  case audio
  case subtitle
}

/// A single codec the resolved `ffmpeg` build can encode and/or decode.
public struct FFmpegCodec: Sendable, Equatable, Identifiable, Comparable {
  /// The name `ffmpeg` accepts for this codec as a `-c:x` value, e.g. `libx265`.
  public var name: String
  /// The description `ffmpeg` prints beside the name in its capability table.
  public var summary: String
  /// The kind of stream this codec applies to.
  public var mediaType: FFmpegMediaType
  /// Whether this build can encode to this codec.
  public var canEncode: Bool
  /// Whether this build can decode from this codec.
  public var canDecode: Bool

  public var id: String { name }

  /**
   The codec this encoder produces, when `ffmpeg` names the two differently
   and says so in a trailing `(codec hevc)` annotation. The family is a valid
   `-c:x` value in its own right — it resolves to whichever encoder the build
   prefers — so it belongs alongside the encoder names wherever a codec is
   chosen or checked.
   */
  public var family: String? {
    guard let start = summary.range(of: "(codec ") else { return nil }
    let family = summary[start.upperBound...]
      .prefix { $0 != ")" }
      .trimmingCharacters(in: .whitespaces)
    return family.isEmpty ? nil : family
  }

  public init(
    name: String,
    summary: String,
    mediaType: FFmpegMediaType,
    canEncode: Bool,
    canDecode: Bool
  ) {
    self.name = name
    self.summary = summary
    self.mediaType = mediaType
    self.canEncode = canEncode
    self.canDecode = canDecode
  }

  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.name.lowercased() < rhs.name.lowercased()
  }
}

/// A container/muxer format the resolved `ffmpeg` build can read and/or write.
public struct FFmpegContainer: Sendable, Equatable, Identifiable, Comparable {
  /// The name `ffmpeg` accepts for this format, e.g. `mov,mp4,m4a`.
  public var name: String
  /// The description `ffmpeg` prints beside the name in its capability table.
  public var summary: String
  /// Whether this build can read (demux) the format.
  public var canDemux: Bool
  /// Whether this build can write (mux) the format.
  public var canMux: Bool

  public var id: String { name }

  public init(name: String, summary: String, canDemux: Bool, canMux: Bool) {
    self.name = name
    self.summary = summary
    self.canDemux = canDemux
    self.canMux = canMux
  }

  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.name.lowercased() < rhs.name.lowercased()
  }
}

/// The version and build configuration of a resolved `ffmpeg` binary.
public struct FFmpegVersionInfo: Sendable, Equatable {
  /// The bare version token, e.g. `6.1.1`.
  public var version: String
  /// The whole first line, e.g. `ffmpeg version 6.1.1 Copyright (c) …`.
  public var bannerLine: String
  /// The `./configure` line the build was compiled with, if reported.
  public var configuration: String?
  /// Normalized `libav*` version strings, e.g. `libavcodec 60.31.102`.
  public var libraryVersions: [String]

  /**
   The numeric components of ``version``, for ordering one build against
   another: `8.1.2` and `n7.1` and `6.1.1-tessus` all reduce to their release
   numbers. Empty for a git snapshot (`N-113579-g4a134eb14f`), whose version
   names no release and which therefore sorts behind every numbered build.
   */
  public var comparableVersion: [UInt] {
    let numbered = version.hasPrefix("n") ? version.dropFirst() : version[...]
    return numbered.prefix { $0.isNumber || $0 == "." }
      .split(separator: ".")
      .compactMap { UInt($0) }
  }

  public init(
    version: String,
    bannerLine: String,
    configuration: String?,
    libraryVersions: [String]
  ) {
    self.version = version
    self.bannerLine = bannerLine
    self.configuration = configuration
    self.libraryVersions = libraryVersions
  }
}

/**
 Everything the app knows about a resolved `ffmpeg` build: its version and
 the containers/codecs it actually supports. Derived entirely by parsing the
 binary's own output, so it honestly reflects an LGPL vs. GPL build.
 */
public struct FFmpegCapabilities: Sendable, Equatable {
  /// The build's version and configuration, if `-version` reported a banner line.
  public var version: FFmpegVersionInfo?
  /// The container formats the build can read and/or write.
  public var containers: [FFmpegContainer]
  /// The video codecs the build can encode and/or decode.
  public var videoCodecs: [FFmpegCodec]
  /// The audio codecs the build can encode and/or decode.
  public var audioCodecs: [FFmpegCodec]
  /// The subtitle codecs the build can encode and/or decode.
  public var subtitleCodecs: [FFmpegCodec]

  public init(
    version: FFmpegVersionInfo?,
    containers: [FFmpegContainer],
    videoCodecs: [FFmpegCodec],
    audioCodecs: [FFmpegCodec],
    subtitleCodecs: [FFmpegCodec]
  ) {
    self.version = version
    self.containers = containers
    self.videoCodecs = videoCodecs
    self.audioCodecs = audioCodecs
    self.subtitleCodecs = subtitleCodecs
  }
}

/// The outcome of probing a resolved `ffmpeg` build.
enum FFmpegProbeOutcome: Sendable, Equatable {
  case success(FFmpegCapabilities)
  /// The binary could not be found or run; carries a user-facing reason.
  case unavailable(String)
}

/**
 A pure parser for `ffmpeg`'s `-version`, `-formats`, `-encoders`, and
 `-decoders` text output. Kept free of any process I/O so it is trivially
 unit-testable against captured sample output.
 */
enum FFmpegOutputParser {

  static func parse(
    version: String,
    formats: String,
    encoders: String,
    decoders: String
  ) -> FFmpegCapabilities {
    let codecs = parseCodecs(encoders: encoders, decoders: decoders)
    return FFmpegCapabilities(
      version: parseVersion(version),
      containers: parseFormats(formats),
      videoCodecs: codecs.video,
      audioCodecs: codecs.audio,
      subtitleCodecs: codecs.subtitle
    )
  }

  static func parseVersion(_ output: String) -> FFmpegVersionInfo? {
    let lines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    guard let bannerLine = lines.first(where: { $0.hasPrefix("ffmpeg version ") }) else {
      return nil
    }
    let version =
      bannerLine
      .dropFirst("ffmpeg version ".count)
      .split(separator: " ", maxSplits: 1).first
      .map(String.init) ?? ""

    var configuration: String?
    var libraryVersions: [String] = []
    for line in lines {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.hasPrefix("configuration:") {
        configuration =
          trimmed
          .dropFirst("configuration:".count)
          .trimmingCharacters(in: .whitespaces)
      } else if trimmed.hasPrefix("lib"), let normalized = normalizedLibrary(trimmed) {
        libraryVersions.append(normalized)
      }
    }
    return FFmpegVersionInfo(
      version: version,
      bannerLine: bannerLine,
      configuration: configuration,
      libraryVersions: libraryVersions
    )
  }

  static func parseFormats(_ output: String) -> [FFmpegContainer] {
    tableRows(in: output).compactMap { row in
      guard row.flags.contains("D") || row.flags.contains("E") else { return nil }
      return FFmpegContainer(
        name: row.name,
        summary: row.summary,
        canDemux: row.flags.contains("D"),
        canMux: row.flags.contains("E")
      )
    }
    .sorted()
  }

  static func parseCodecs(
    encoders: String,
    decoders: String
  ) -> (video: [FFmpegCodec], audio: [FFmpegCodec], subtitle: [FFmpegCodec]) {
    var codecsByName: [String: FFmpegCodec] = [:]

    func ingest(_ output: String, encode: Bool) {
      for row in tableRows(in: output) {
        guard let mediaType = mediaType(for: row.flags) else { continue }
        var codec =
          codecsByName[row.name]
          ?? FFmpegCodec(
            name: row.name,
            summary: row.summary,
            mediaType: mediaType,
            canEncode: false,
            canDecode: false
          )
        if codec.summary.isEmpty { codec.summary = row.summary }
        if encode { codec.canEncode = true } else { codec.canDecode = true }
        codecsByName[row.name] = codec
      }
    }

    ingest(encoders, encode: true)
    ingest(decoders, encode: false)

    let all = Array(codecsByName.values)
    return (
      video: all.filter { $0.mediaType == .video }.sorted(),
      audio: all.filter { $0.mediaType == .audio }.sorted(),
      subtitle: all.filter { $0.mediaType == .subtitle }.sorted()
    )
  }

  /**
   The data rows of an `ffmpeg` capability table: everything after the
   dashed separator, split into flags/name/summary.
   */
  private static func tableRows(in output: String) -> [FlaggedRow] {
    var rows: [FlaggedRow] = []
    var reachedBody = false
    for rawLine in output.split(separator: "\n", omittingEmptySubsequences: false) {
      let line = String(rawLine)
      if !reachedBody {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty, trimmed.allSatisfy({ $0 == "-" }) { reachedBody = true }
        continue
      }
      let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
      guard fields.count >= 2 else { continue }
      rows.append(
        FlaggedRow(
          flags: fields[0],
          name: fields[1],
          summary: fields.dropFirst(2).joined(separator: " ")
        )
      )
    }
    return rows
  }

  private static func mediaType(for flags: String) -> FFmpegMediaType? {
    switch flags.first {
      case "V": .video
      case "A": .audio
      case "S": .subtitle
      default: nil
    }
  }

  /**
   Collapses a `libavcodec     60. 31.102 / 60. 31.102` line into
   `libavcodec 60.31.102`.
   */
  private static func normalizedLibrary(_ line: String) -> String? {
    let compiled = line.split(separator: "/", maxSplits: 1).first.map(String.init) ?? line
    let fields = compiled.split(whereSeparator: \.isWhitespace).map(String.init)
    guard let name = fields.first, fields.count >= 2 else { return nil }
    return "\(name) \(fields.dropFirst().joined())"
  }

  /**
   A flag/name/summary triple from a table row like
   `DE mov,mp4,m4a  QuickTime / MOV`.
   */
  private struct FlaggedRow {
    var flags: String
    var name: String
    var summary: String
  }
}

/**
 Runs a resolved `ffmpeg` binary off the main actor to discover its version
 and supported formats. All process work stays inside these methods, so the
 type is `Sendable` and safe to hand to a background task.
 */
struct FFmpegProbe: Sendable {
  /// The `ffmpeg` executable to probe.
  let ffmpegURL: URL

  /**
   Probes the binary, returning its capabilities or a reason it could not
   be run.
   */
  func run() async -> FFmpegProbeOutcome {
    guard FileManager.default.isExecutableFile(atPath: ffmpegURL.path(percentEncoded: false)) else {
      return .unavailable(
        String(
          localized: "No runnable ffmpeg at “\(ffmpegURL.path(percentEncoded: false))”",
          bundle: #bundle
        )
      )
    }
    do {
      async let version = capture(["-hide_banner", "-version"])
      async let formats = capture(["-hide_banner", "-formats"])
      async let encoders = capture(["-hide_banner", "-encoders"])
      async let decoders = capture(["-hide_banner", "-decoders"])
      return .success(
        FFmpegOutputParser.parse(
          version: try await version,
          formats: try await formats,
          encoders: try await encoders,
          decoders: try await decoders
        )
      )
    } catch {
      return .unavailable(error.userMessage)
    }
  }

  private func capture(_ arguments: [String]) async throws -> String {
    let process = Process()
    process.executableURL = ffmpegURL
    process.arguments = arguments
    process.standardError = FileHandle.nullDevice
    process.standardInput = Pipe()

    let data = try await process.runCapturingStandardOutput()

    guard process.terminationStatus == 0 else {
      throw FFmpegToolError.probeUnavailable(
        detail: String(
          localized: "ffmpeg exited with code \(process.terminationStatus, format: .number).",
          bundle: #bundle
        )
      )
    }
    // Decoded lossily on purpose: ffmpeg's capability listings can carry a
    // stray byte, and losing the whole listing to a nil is worse than a U+FFFD.
    // swiftlint:disable:next optional_data_string_conversion
    return String(decoding: data, as: UTF8.self)
  }
}
