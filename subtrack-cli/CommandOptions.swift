import Foundation

/**
 The outcome of parsing CLI arguments: either usable options or a request for
 help text (which is control flow, not an error).
 */
enum ParseResult {
  case options(CommandOptions)
  case help(String)
}

/**
 Parsed `subtrack` command-line options. Mirrors the VideoSlimmer CLI so the
 GUI and command line stay at parity, sharing one engine.
 */
struct CommandOptions {

  static let usageText = String(
    localized: """
      OVERVIEW: Removes unneeded audio and subtitle tracks from a movie container
      using FFMPEG. No transcoding occurs unless necessary; kept tracks are copied
      to a new container without modification.

      USAGE: subtrack [options] <input> <output>

      ARGUMENTS:
        <input>                 The video file to slim
        <output>                The output path for the slimmed video file

      OPTIONS:
        --ffmpeg <path>         Path to ffmpeg executable
        --ffprobe <path>        Path to ffprobe executable
        -l, --language <lang>   Audio/subtitle languages to preserve, in priority
                                order — the first leads the output and its audio
                                becomes the default track (repeatable)
        -n, --no-language       Preserve tracks with no language metadata
        --video-codec <codec>   Preferred video codecs (repeatable)
        --audio-codec <codec>   Preferred audio codecs (repeatable)
        --subtitle-codec <c>    Preferred subtitle codecs (repeatable)
        --video-transcode <c>   Codec to transcode non-preferred video to
        --audio-transcode <c>   Codec to transcode non-preferred audio to
        --video-option <opt>    Extra ffmpeg option when transcoding video (repeatable)
        --audio-option <opt>    Extra ffmpeg option when transcoding audio (repeatable)
        --include-other-audio   Include non-default audio (e.g. commentary)
        -d, --dry-run           Print the operations instead of performing them
        --skip-noops            Skip files that would not change
        --suppress-stderr       Discard ffmpeg/ffprobe stderr output
        --skip-verify           Skip post-process verification of the output
        -h, --help              Show this help
      """
  )

  private static let helpFlags: Set<String> = ["-h", "--help"]

  var ffmpeg: URL?
  var ffprobe: URL?
  var languages = ["eng"]
  var noLanguage = false
  var videoCodecs = ["av1", "hevc", "h264"]
  var audioCodecs = ["truehd", "dts", "eac3", "ac3", "flac", "aac"]
  var subtitleCodecs = ["hdmv_pgs_subtitle", "subrip"]
  var videoTranscode = "hevc"
  var audioTranscode = "eac3"
  var videoOptions = ["-preset", "veryslow"]
  var audioOptions = [String]()
  var includeOtherAudio = false
  var dryRun = false
  var skipNoops = false
  var suppressStderr = false
  var skipVerify = false
  var input: URL?
  var output: URL?

  /// The rules described by these options.
  var rules: SlimRules {
    SlimRules(
      languages: languages,
      preserveNoLanguages: noLanguage,
      includeOtherAudio: includeOtherAudio,
      videoPreferredCodecs: videoCodecs,
      videoConversionCodec: videoTranscode,
      videoConversionOptions: videoOptions,
      audioPreferredCodecs: audioCodecs,
      audioConversionCodec: audioTranscode,
      audioConversionOptions: audioOptions,
      subtitlePreferredCodecs: subtitleCodecs
    )
  }

  /// Parses arguments (excluding the executable name).
  static func parse(_ arguments: [String]) throws -> ParseResult {
    var scanner = ArgumentScanner(arguments: arguments)
    while let argument = scanner.nextArgument() {
      guard !helpFlags.contains(argument) else { return .help(usageText) }
      try scanner.apply(argument)
    }
    return .options(try scanner.finish())
  }
}

/**
 Walks the argument list once, folding each argument into a ``CommandOptions``
 and collecting the positional arguments left over.

 Which flags exist, and what each one sets, is described by the tables below
 rather than by a switch, so a flag and its two spellings are one entry.
 */
private struct ArgumentScanner {

  /// Flags that take no value and simply turn something on.
  private let booleanFlags: [String: WritableKeyPath<CommandOptions, Bool>] = [
    "-n": \.noLanguage,
    "--no-language": \.noLanguage,
    "--include-other-audio": \.includeOtherAudio,
    "-d": \.dryRun,
    "--dry-run": \.dryRun,
    "--skip-noops": \.skipNoops,
    "--suppress-stderr": \.suppressStderr,
    "--skip-verify": \.skipVerify
  ]

  /// Flags whose value names an executable on disk.
  private let pathFlags: [String: WritableKeyPath<CommandOptions, URL?>] = [
    "--ffmpeg": \.ffmpeg,
    "--ffprobe": \.ffprobe
  ]

  /// Flags whose value replaces a single string.
  private let stringFlags: [String: WritableKeyPath<CommandOptions, String>] = [
    "--video-transcode": \.videoTranscode,
    "--audio-transcode": \.audioTranscode
  ]

  /// Repeatable flags whose values accumulate into a list.
  private let listFlags: [String: WritableKeyPath<CommandOptions, [String]>] = [
    "-l": \.languages,
    "--language": \.languages,
    "--video-codec": \.videoCodecs,
    "--audio-codec": \.audioCodecs,
    "--subtitle-codec": \.subtitleCodecs,
    "--video-option": \.videoOptions,
    "--audio-option": \.audioOptions
  ]

  private let arguments: [String]
  private var index: Int
  private var options = CommandOptions()
  private var positionals = [String]()
  private var clearedLists = Set<WritableKeyPath<CommandOptions, [String]>>()

  init(arguments: [String]) {
    self.arguments = arguments
    self.index = arguments.startIndex
  }

  /// The next unread argument, or `nil` once the list is exhausted.
  mutating func nextArgument() -> String? {
    guard index < arguments.endIndex else { return nil }
    defer { index = arguments.index(after: index) }
    return arguments[index]
  }

  /// Folds one argument — a flag and any value it takes, or a positional — into the options.
  mutating func apply(_ argument: String) throws {
    if let keyPath = booleanFlags[argument] {
      options[keyPath: keyPath] = true
    } else if let keyPath = pathFlags[argument] {
      let path = try nextValue(for: argument)
      options[keyPath: keyPath] = URL(filePath: path, directoryHint: .notDirectory)
    } else if let keyPath = stringFlags[argument] {
      let value = try nextValue(for: argument)
      options[keyPath: keyPath] = value
    } else if let keyPath = listFlags[argument] {
      let value = try nextValue(for: argument)
      append(value, to: keyPath)
    } else {
      try takePositional(argument)
    }
  }

  /// The scanned options, with the input and output paths taken from the positionals.
  mutating func finish() throws -> CommandOptions {
    guard positionals.count == 2 else { throw CLIUsageError.wrongArgumentCount }
    options.input = URL(filePath: positionals[0], directoryHint: .notDirectory)
    options.output = URL(filePath: positionals[1], directoryHint: .notDirectory)
    return options
  }

  private mutating func nextValue(for flag: String) throws -> String {
    guard let value = nextArgument() else { throw CLIUsageError.missingValue(flag: flag) }
    return value
  }

  /**
   Appends to a repeatable option, clearing the built-in default the first time
   the option appears (matching swift-argument-parser semantics).
   */
  private mutating func append(
    _ value: String,
    to keyPath: WritableKeyPath<CommandOptions, [String]>
  ) {
    if clearedLists.insert(keyPath).inserted { options[keyPath: keyPath] = [] }
    options[keyPath: keyPath].append(value)
  }

  private mutating func takePositional(_ argument: String) throws {
    guard !looksLikeOption(argument) else { throw CLIUsageError.unknownOption(argument) }
    positionals.append(argument)
  }

  private func looksLikeOption(_ argument: String) -> Bool {
    argument.hasPrefix("-") && argument != "-"
  }
}
