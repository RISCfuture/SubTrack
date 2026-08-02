import SwiftUI

/**
 A hierarchical, searchable view of what a resolved `ffmpeg` build supports:
 a build-info header, then disclosure accordions for containers and the
 video, audio, and subtitle codecs. Each accordion reveals a compact
 three-column list showing the format identifier, its human name, and
 encode/decode (or read/write) support. Driven entirely by a probed ``FFmpegCapabilities``
 value so an LGPL build honestly shows no x264/x265 while a full build shows them.
 */
struct FFmpegFormatsView: View {
  private let capabilities: FFmpegCapabilities
  private let showsFullVersionLink: Bool
  @State private var searchText = ""
  @State private var expandedCategories: Set<Category> = [.containers, .video]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading) {
        if let version = capabilities.version {
          BuildSummaryCard(version: version)
        }
        if !containerEntries.isEmpty {
          FormatDisclosure(
            title: "Containers",
            supportTitle: "Read / Write",
            entries: containerEntries,
            isExpanded: expansion(for: .containers)
          )
        }
        CodecDisclosure(
          title: "Video Codecs",
          codecs: capabilities.videoCodecs,
          query: searchText,
          isExpanded: expansion(for: .video)
        )
        CodecDisclosure(
          title: "Audio Codecs",
          codecs: capabilities.audioCodecs,
          query: searchText,
          isExpanded: expansion(for: .audio)
        )
        CodecDisclosure(
          title: "Subtitle Codecs",
          codecs: capabilities.subtitleCodecs,
          query: searchText,
          isExpanded: expansion(for: .subtitle)
        )
        if showsFullVersionLink {
          MissingCodecsLink().padding(.top)
        }
      }
      .padding()
    }
    .searchable(text: $searchText, prompt: Text("Filter"))
    .navigationTitle("Supported Formats")
  }

  // MARK: - Filtering

  private var containerEntries: [FormatEntry] {
    capabilities.containers.map(FormatEntry.init(container:)).matching(searchText)
  }

  // MARK: - Expansion

  private var isFiltering: Bool { !searchText.trimmingCharacters(in: .whitespaces).isEmpty }

  /**
   Creates the formats view over an already-probed build.

   - Parameters:
     - capabilities: The containers and codecs the resolved build reported.
     - showsFullVersionLink: In the App Store build the bundled ffmpeg
       is an LGPL build, so the list honestly reports fewer encoders. Pass `true`
       there to offer a link to the fuller downloadable build.
   */
  init(capabilities: FFmpegCapabilities, showsFullVersionLink: Bool = false) {
    self.capabilities = capabilities
    self.showsFullVersionLink = showsFullVersionLink
  }

  /**
   A binding that forces every group open while a filter is active — so
   matches are never hidden behind a collapsed accordion — and otherwise
   tracks the user's per-group choice.
   */
  private func expansion(for category: Category) -> Binding<Bool> {
    Binding(
      get: { isFiltering || expandedCategories.contains(category) },
      set: { expand in
        if expand {
          expandedCategories.insert(category)
        } else {
          expandedCategories.remove(category)
        }
      }
    )
  }

  private enum Category: Hashable { case containers, video, audio, subtitle }
}

// MARK: - Codec accordion

/**
 One codec category's accordion, rendered only while the query matches at
 least one of its codecs so an empty group never shows an empty table.
 */
private struct CodecDisclosure: View {
  let title: LocalizedStringKey
  let codecs: [FFmpegCodec]
  let query: String
  @Binding var isExpanded: Bool

  var body: some View {
    let entries = codecs.map(FormatEntry.init(codec:)).matching(query)
    if !entries.isEmpty {
      FormatDisclosure(
        title: title,
        supportTitle: "Decode / Encode",
        entries: entries,
        isExpanded: $isExpanded
      )
    }
  }
}

// MARK: - Full-version link

/**
 Shown only in the App Store build, where the bundled LGPL ffmpeg honestly
 lists fewer encoders. Points at the downloadable build rather than padding
 the list with codecs this build can't actually use.
 */
private struct MissingCodecsLink: View {
  var body: some View {
    Button {
      HelpAnchor.editions.open()
    } label: {
      Label("Missing codecs?", systemImage: "questionmark.circle")
    }
    .buttonStyle(.link)
    .help(
      "The downloadable version of SubTrack bundles a fuller ffmpeg build. Click to learn more."
    )
    .accessibilityIdentifier("formats.fullVersionLink")
  }
}

// MARK: - Header

private struct BuildSummaryCard: View {
  private static let cardCornerRadius: CGFloat = 10

  let version: FFmpegVersionInfo

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(version.bannerLine).font(.headline)
      if let configuration = version.configuration {
        Text(configuration).font(.caption).foregroundStyle(.secondary)
      }
      if !version.libraryVersions.isEmpty {
        Text(version.libraryVersions.joined(separator: " · "))
          .font(.caption2).foregroundStyle(.tertiary)
      }
    }
    .textSelection(.enabled)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding()
    .background(.quaternary, in: RoundedRectangle(cornerRadius: Self.cardCornerRadius))
  }
}

// MARK: - Accordion + table

/// One collapsible category whose content is a compact, non-scrolling table.
private struct FormatDisclosure: View {
  let title: LocalizedStringKey
  let supportTitle: LocalizedStringKey
  let entries: [FormatEntry]
  @Binding var isExpanded: Bool

  var body: some View {
    DisclosureGroup(isExpanded: $isExpanded) {
      FormatTable(entries: entries, supportTitle: supportTitle)
        .padding(.top, 4)
    } label: {
      Text("\(Text(title)) (\(entries.count))")
        .font(.headline)
        .monospacedDigit()
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }
  }
}

/**
 The rows of one category, laid out by hand rather than with `Table`. A
 `Table` has no intrinsic height, so embedding one in scrolling content means
 guessing a row height — and every point that guess overshoots becomes a blank
 row, hundreds of them across a real ffmpeg build's format list. A `LazyVStack`
 of fixed-width columns sizes itself to its content and stays lazy.
 */
private struct FormatTable: View {
  let entries: [FormatEntry]
  let supportTitle: LocalizedStringKey

  var body: some View {
    LazyVStack(spacing: 0) {
      FormatTableHeader(supportTitle: supportTitle)
      Divider()
      ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
        FormatRow(entry: entry, isShaded: index.isMultiple(of: 2))
      }
    }
  }
}

/**
 The column titles above one category's rows, laid out on the same geometry
 as the rows themselves.
 */
private struct FormatTableHeader: View {
  let supportTitle: LocalizedStringKey

  var body: some View {
    FormatColumns {
      Text("Identifier")
    } name: {
      Text("Name")
    } support: {
      Text(supportTitle)
    }
    .font(.subheadline)
    .foregroundStyle(.secondary)
  }
}

/// One format's row, shaded on alternate rows so a long list stays readable.
private struct FormatRow: View {
  let entry: FormatEntry
  let isShaded: Bool

  var body: some View {
    FormatColumns {
      Text(entry.identifier).font(.body.monospaced()).help(entry.identifier)
    } name: {
      Text(entry.name.isEmpty ? "—" : entry.name)
        .foregroundStyle(entry.name.isEmpty ? .secondary : .primary)
        .help(entry.name)
    } support: {
      SupportCell(entry: entry)
    }
    .lineLimit(1)
    .background { if isShaded { Rectangle().fill(.quinary) } }
    .accessibilityIdentifier("formats.entry.\(entry.identifier)")
  }
}

/**
 The fixed geometry the header and every row share, declared in one place so
 the two can't drift out of alignment.
 */
private enum FormatColumn {
  /// Fits the long-but-typical ffmpeg identifiers (`pcm_s24daud`, `libopenjpeg`).
  static let identifierWidth: CGFloat = 150
  /// Fits the two direction glyphs under the widest heading, "Decode / Encode".
  static let supportWidth: CGFloat = 108
  /// Tight enough that a build's several hundred formats stay scannable.
  static let rowInsets = EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)
}

/**
 The shared three-column geometry that keeps every row aligned with the
 header above it.
 */
private struct FormatColumns<Identifier: View, Name: View, Support: View>: View {
  @ViewBuilder let identifier: Identifier
  @ViewBuilder let name: Name
  @ViewBuilder let support: Support

  var body: some View {
    HStack {
      identifier.frame(width: FormatColumn.identifierWidth, alignment: .leading)
      name.frame(maxWidth: .infinity, alignment: .leading)
      support.frame(width: FormatColumn.supportWidth, alignment: .leading)
    }
    .padding(FormatColumn.rowInsets)
  }
}

// MARK: - Support cell

/**
 The two capability glyphs for one row: an input direction (decode / read)
 and an output direction (encode / write), each lit when supported.
 */
private struct SupportCell: View {
  let entry: FormatEntry

  var body: some View {
    HStack(spacing: 10) {
      DirectionIcon(capability: entry.input, isActive: entry.canInput, identifier: entry.identifier)
      DirectionIcon(
        capability: entry.output,
        isActive: entry.canOutput,
        identifier: entry.identifier
      )
    }
    .imageScale(.medium)
    .accessibilityElement(children: .combine)
  }
}

private struct DirectionIcon: View {
  let capability: Capability
  let isActive: Bool
  let identifier: String

  var body: some View {
    Image(systemName: isActive ? "\(capability.symbol).fill" : capability.symbol)
      .foregroundStyle(isActive ? .primary : .secondary)
      .help(capability.title)
      .accessibilityLabel(capability.accessibilityLabel(identifier: identifier, isActive: isActive))
  }
}

/**
 A supported direction. The input directions (decode / read) point down, the
 output directions (encode / write) point up.
 */
private enum Capability {
  case decode, encode, read, write

  var symbol: String {
    switch self {
      case .decode, .read: "arrow.down.circle"
      case .encode, .write: "arrow.up.circle"
    }
  }

  var title: String {
    switch self {
      case .decode: String(localized: "Decode")
      case .encode: String(localized: "Encode")
      case .read: String(localized: "Read")
      case .write: String(localized: "Write")
    }
  }

  func accessibilityLabel(identifier: String, isActive: Bool) -> String {
    switch (self, isActive) {
      case (.decode, true): String(localized: "Decodes \(identifier)")
      case (.decode, false): String(localized: "Does not decode \(identifier)")
      case (.encode, true): String(localized: "Encodes \(identifier)")
      case (.encode, false): String(localized: "Does not encode \(identifier)")
      case (.read, true): String(localized: "Reads \(identifier)")
      case (.read, false): String(localized: "Does not read \(identifier)")
      case (.write, true): String(localized: "Writes \(identifier)")
      case (.write, false): String(localized: "Does not write \(identifier)")
    }
  }
}

// MARK: - Row model

/**
 A container or codec flattened into the columns the table renders, carrying
 which capability each of its two support glyphs represents.
 */
private struct FormatEntry: Identifiable {
  let id: String
  let identifier: String
  let name: String
  let input: Capability
  let canInput: Bool
  let output: Capability
  let canOutput: Bool

  init(codec: FFmpegCodec) {
    id = codec.name
    identifier = codec.name
    name = codec.summary
    input = .decode
    canInput = codec.canDecode
    output = .encode
    canOutput = codec.canEncode
  }

  init(container: FFmpegContainer) {
    id = container.name
    identifier = container.name
    name = container.summary
    input = .read
    canInput = container.canDemux
    output = .write
    canOutput = container.canMux
  }
}

extension [FormatEntry] {
  /**
   The entries whose identifier or name contains `query`, matched
   case-insensitively. An empty or whitespace-only query matches everything.
   */
  fileprivate func matching(_ query: String) -> [FormatEntry] {
    let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
    guard !needle.isEmpty else { return self }
    return filter { entry in
      [entry.identifier, entry.name].contains { $0.lowercased().contains(needle) }
    }
  }
}

#if DEBUG
  #Preview("Formats — download (full, no link)") {
    FFmpegFormatsView(capabilities: .previewSample)
      .frame(width: 540, height: 640)
  }

  #Preview("Formats — App Store (LGPL, with link)") {
    FFmpegFormatsView(capabilities: .previewLGPLSample, showsFullVersionLink: true)
      .frame(width: 540, height: 640)
  }
#endif
