import Foundation

/// A placeholder an ``OutputNameFormat`` substitutes when it names a slimmed file.
public enum OutputNameToken: String, Codable, CaseIterable, Sendable {
  /// The source file's name without its extension.
  case originalName = "name"

  /// The file's 1-based position in its queue.
  case sequenceNumber = "n"

  /// The token's `{…}` form as it appears in a template.
  public var placeholder: String { "{\(rawValue)}" }

  /// The token's name in the format editor.
  public var title: String {
    switch self {
      case .originalName: String(localized: "Original Name")
      case .sequenceNumber: String(localized: "Number")
    }
  }

  /// A stand-in shown when the format is previewed against no real file.
  public var sample: String {
    switch self {
      case .originalName: String(localized: "Movie")
      case .sequenceNumber: "1"
    }
  }
}

/**
 One piece of a parsed ``OutputNameFormat``: literal text, or a token to
 substitute per file.
 */
public enum OutputNameSegment: Equatable, Sendable {
  case text(String)
  case token(OutputNameToken)

  /// Whether this piece is substituted per file rather than written literally.
  public var isToken: Bool {
    switch self {
      case .token: true
      case .text: false
    }
  }
}

/**
 A user-editable template for the name of a slimmed file, written as literal text
 with `{name}` and `{n}` placeholders — `{{` and `}}` stand for literal braces.

 The template names the file's *base* only; ``fileName(for:position:)`` appends
 the source's own extension, because slimming remuxes into the same container and
 a name claiming otherwise would lie about its contents.

 ``segments`` is the parsed view the editor binds to, and
 ``init(segments:)`` writes one back. Parsing is total: an unrecognized
 placeholder such as `{foo}` is literal text, so a typo never destroys what the
 user typed. Round-tripping normalizes stray braces into their escaped form.
 */
public struct OutputNameFormat: Sendable, Equatable {

  /// The default format, which appends " (slimmed)" to each source's name.
  public static let slimmed = Self(template: "{name} (slimmed)")

  /// Characters no name component may contain, replaced with a hyphen.
  private static let illegalCharacters = CharacterSet(charactersIn: "/:")

  /**
   Characters a name can't usefully begin or end with: whitespace, and the
   dots that would hide the file or be mistaken for an extension.
   */
  private static let trimmedCharacters = CharacterSet.whitespacesAndNewlines
    .union(CharacterSet(charactersIn: "."))

  /// The raw template text, the form persisted with a preset or queue.
  public var template: String

  /// The template parsed into literal text and tokens.
  public var segments: [OutputNameSegment] { Self.parse(template) }

  /**
   The name this format renders against no particular file, for showing the
   user what it produces before anything is queued.
   */
  public var sampleFileName: String {
    let base = Self.sanitize(render { $0.sample })
    return base.isEmpty ? String(localized: "Movie.mkv") : "\(base).mkv"
  }

  public init(template: String) {
    self.template = template
  }

  /**
   Builds a format from the editor's parsed pieces, escaping any braces the
   user typed as literal text.
   */
  public init(segments: [OutputNameSegment]) {
    self.init(template: Self.serialize(segments))
  }

  /**
   The file name a slimmed copy of `source` gets when the user has named that
   one file explicitly: `base` sanitized, plus the source's own extension —
   the same extension policy every formatted name follows, for the same
   reason.
   */
  public static func fileName(customBase base: String, for source: URL) -> String {
    appendingExtension(of: source, to: sanitize(base, fallingBackTo: source))
  }

  /**
   Where a slimmed copy of `source` is written when the user has named that
   one file explicitly: inside `destination` when the queue has one,
   otherwise beside the source.
   */
  public static func outputURL(customBase base: String, for source: URL, in destination: URL?)
    -> URL
  {
    outputURL(named: fileName(customBase: base, for: source), for: source, in: destination)
  }

  private static func outputURL(named name: String, for source: URL, in destination: URL?) -> URL {
    let folder = destination ?? source.deletingLastPathComponent()
    return folder.appending(path: name, directoryHint: .notDirectory)
  }

  private static func appendingExtension(of source: URL, to base: String) -> String {
    let pathExtension = source.pathExtension
    return pathExtension.isEmpty ? base : "\(base).\(pathExtension)"
  }

  /**
   `name` sanitized into something a file system accepts, falling back to
   `source`'s own base name when nothing usable survives — so an output file
   always has a name.
   */
  private static func sanitize(_ name: String, fallingBackTo source: URL) -> String {
    let sanitized = sanitize(name)
    return sanitized.isEmpty ? source.deletingPathExtension().lastPathComponent : sanitized
  }

  /**
   The file name a slimmed copy of `source` gets at `position`: the rendered
   base name plus the source's own extension.
   */
  public func fileName(for source: URL, position: Int) -> String {
    Self.appendingExtension(of: source, to: baseName(for: source, position: position))
  }

  /**
   Where a slimmed copy of `source` at `position` is written: inside
   `destination` when the queue has one, otherwise beside the source.
   */
  public func outputURL(for source: URL, position: Int, in destination: URL?) -> URL {
    Self.outputURL(named: fileName(for: source, position: position), for: source, in: destination)
  }

  /**
   The base name (no extension) rendered for `source` at `position`, sanitized
   into something a file system accepts.
   */
  private func baseName(for source: URL, position: Int) -> String {
    Self.sanitize(
      render { token in
        switch token {
          case .originalName: source.deletingPathExtension().lastPathComponent
          case .sequenceNumber: String(position)
        }
      },
      fallingBackTo: source
    )
  }

  /// Joins the segments, substituting each token with `substitution`.
  private func render(_ substitution: (OutputNameToken) -> String) -> String {
    segments
      .map { segment in
        switch segment {
          case .text(let text): text
          case .token(let token): substitution(token)
        }
      }
      .joined()
  }
}

// MARK: - Template parsing

extension OutputNameFormat {

  private static func parse(_ template: String) -> [OutputNameSegment] {
    var segments = [OutputNameSegment]()
    var literal = ""
    var index = template.startIndex

    func flushLiteral() {
      guard !literal.isEmpty else { return }
      segments.append(.text(literal))
      literal = ""
    }

    while index < template.endIndex {
      let character = template[index]
      let next = template.index(after: index)
      if character.isBrace, template[next...].first == character {
        literal.append(character)
        index = template.index(after: next)
      } else if character == "{", let token = token(in: template, openingAt: index) {
        flushLiteral()
        segments.append(.token(token.token))
        index = token.end
      } else {
        literal.append(character)
        index = next
      }
    }
    flushLiteral()
    return segments
  }

  /**
   The token whose `{…}` starts at `index`, and where it ends; `nil` when the
   brace opens something that isn't a recognized token.
   */
  private static func token(
    in template: String,
    openingAt index: String.Index
  ) -> (token: OutputNameToken, end: String.Index)? {
    let body = template.index(after: index)
    guard
      let close = template[body...].firstIndex(of: "}"),
      let token = OutputNameToken(rawValue: String(template[body..<close]))
    else { return nil }
    return (token, template.index(after: close))
  }

  private static func serialize(_ segments: [OutputNameSegment]) -> String {
    segments
      .map { segment in
        switch segment {
          case .text(let text): escape(text)
          case .token(let token): token.placeholder
        }
      }
      .joined()
  }

  private static func escape(_ text: String) -> String {
    String(text.flatMap { $0.isBrace ? [$0, $0] : [$0] })
  }

  private static func sanitize(_ name: String) -> String {
    name
      .components(separatedBy: illegalCharacters)
      .joined(separator: "-")
      .trimmingCharacters(in: trimmedCharacters)
  }
}

extension Character {
  fileprivate var isBrace: Bool { self == "{" || self == "}" }
}

// MARK: - Persistence

/**
 Encodes as the bare template string, so a stored format reads as what the
 user typed rather than as a wrapper object.
 */
extension OutputNameFormat: Codable {
  public init(from decoder: any Decoder) throws {
    try self.init(template: decoder.singleValueContainer().decode(String.self))
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(template)
  }
}

// MARK: - Conflicts

/**
 A reason an ``OutputNameFormat`` can't safely name the files in a queue.
 Reported to the user and blocks the queue from running, rather than letting
 a run silently destroy a file.
 */
public enum OutputNameConflict: Hashable, Sendable {

  /// Two or more sources this format sends to the same output path.
  case duplicateOutputs(name: String, sources: [URL])

  /// Sources whose output path is the source file itself.
  case overwritesSource(sources: [URL])

  /// The files this conflict is about.
  public var sources: [URL] {
    switch self {
      case .duplicateOutputs(_, let sources), .overwritesSource(let sources): sources
    }
  }

  /// A one-line explanation naming what would go wrong.
  public var message: String {
    switch self {
      case let .duplicateOutputs(name, sources):
        String(
          localized: "\(sources.count, format: .number) files would all be saved as “\(name)”."
        )
      case .overwritesSource(let sources) where sources.count == 1:
        String(localized: "“\(sources[0].lastPathComponent)” would overwrite its own source file.")
      case .overwritesSource(let sources):
        String(
          localized:
            "\(sources.count, format: .number) files would overwrite their own source files."
        )
    }
  }

  /**
   Every way the given source-to-output pairings would destroy a file: two
   sources landing on one path, and a source landing on itself. Empty when
   the pairings are safe.
   */
  public static func conflicts(in outputs: [(source: URL, output: URL)]) -> [Self] {
    duplicates(in: outputs) + overwrites(in: outputs)
  }

  private static func duplicates(in outputs: [(source: URL, output: URL)]) -> [Self] {
    Dictionary(grouping: outputs) { $0.output.standardizedFileURL }
      .filter { $0.value.count > 1 }
      .sorted { $0.key.path(percentEncoded: false) < $1.key.path(percentEncoded: false) }
      .map { .duplicateOutputs(name: $0.key.lastPathComponent, sources: $0.value.map(\.source)) }
  }

  private static func overwrites(in outputs: [(source: URL, output: URL)]) -> [Self] {
    let overwritten =
      outputs
      .filter { $0.output.standardizedFileURL == $0.source.standardizedFileURL }
      .map(\.source)
    return overwritten.isEmpty ? [] : [.overwritesSource(sources: overwritten)]
  }
}

extension OutputNameFormat {

  /**
   Every way this format fails to name `sources` written into `destination`
   (or beside each source when there is none). `sources` is taken in queue
   order, so each file's position matches the `{n}` it would be given.
   */
  public func conflicts(naming sources: [URL], into destination: URL?) -> [OutputNameConflict] {
    OutputNameConflict.conflicts(
      in: sources.enumerated().map { position, source in
        (source: source, output: outputURL(for: source, position: position + 1, in: destination))
      }
    )
  }
}
