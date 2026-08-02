import SwiftUI

/// One labelled fact about a track, as the Override tab lists them.
struct TrackFact: Identifiable {
  let name: String
  let value: String

  var id: String { name }
}

/**
 A track's metadata as one compact block: label/value pairs aligned in a grid,
 so a dozen facts read as a single form row rather than a dozen ruled ones.
 */
struct TrackFactsView: View {
  let facts: [TrackFact]

  var body: some View {
    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 2) {
      ForEach(facts) { fact in
        GridRow {
          Text(fact.name)
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.trailing)
          Text(fact.value)
            .lineLimit(1)
            .truncationMode(.tail)
        }
      }
    }
    .font(.caption)
  }
}

extension PlannedTrack {

  /**
   How the track reads in a picker row: its position in the file, what kind it
   is, its language and codec — and, when the run would leave it out, that it
   is skipped. Kept tracks say nothing, because the picker already marks the
   selected row with a checkmark of its own.
   */
  var pickerTitle: String {
    let described = [String(index), typeName, languageName, stream.codecName]
      .joined(separator: " · ")
    return isIncluded ? described : String(localized: "\(described) (skipped)", bundle: #bundle)
  }

  /**
   The codec the output will hold this track in, qualified by the shape of what
   it carries: "ac3 5.1", "h264 1080p", "subrip". A converted track names its
   target behind an arrow, because that — not the source's codec — is what the
   output will be in.
   */
  var outputCodecSummary: String {
    // Joined rather than localized: both halves are localized already, and a
    // key of "%@ %@" tells a translator nothing and collides with every other
    // two-value join in the catalog.
    [outputCodecName, shape].compactMap(\.self).joined(separator: " ")
  }

  /**
   Everything the probe knows about this track, in the order the tab lists it:
   what it is, how it is tagged, and what shape its media takes.
   */
  var facts: [TrackFact] {
    [
      TrackFact(name: String(localized: "Type", bundle: #bundle), value: typeName),
      TrackFact(name: String(localized: "Codec", bundle: #bundle), value: codecDescription),
      TrackFact(name: String(localized: "Language", bundle: #bundle), value: languageName),
      stream.title.map { TrackFact(name: String(localized: "Title", bundle: #bundle), value: $0) }
    ].compactMap(\.self) + mediaFacts + tagFacts
  }

  /**
   Every fact about the track as one block, for a tooltip over a row too narrow
   to hold them. What the columns had to leave out is here.
   */
  var factsSummary: String {
    facts.map { "\($0.name): \($0.value)" }.joined(separator: "\n")
  }

  var typeName: String {
    switch type {
      case .video: String(localized: "Video", bundle: #bundle)
      case .audio: String(localized: "Audio", bundle: #bundle)
      case .subtitle: String(localized: "Subtitle", bundle: #bundle)
    }
  }

  /// The glyph standing in for ``typeName`` where a column is too narrow for the word.
  var typeSymbolName: String {
    switch type {
      case .video: "film"
      case .audio: "waveform"
      case .subtitle: "captions.bubble"
    }
  }

  /**
   The track's language named in the user's own language, falling back to the
   raw tag when the catalog doesn't recognize it.
   */
  var languageName: String {
    guard let language = stream.language else {
      return String(localized: "Untagged", bundle: #bundle)
    }
    return LanguageCatalog.name(for: language) ?? language
  }

  private var index: UInt { stream.index }

  /**
   The codec, qualified by its encoding profile when the probe reported one
   (e.g. "h264 (High)").
   */
  private var codecDescription: String {
    guard let profile else { return stream.codecName }
    return String(localized: "\(stream.codecName) (\(profile))", bundle: #bundle)
  }

  private var profile: String? {
    switch stream {
      case let video as VideoStream: video.profile
      case let audio as AudioStream: audio.profile
      default: nil
    }
  }

  /// The codec the run leaves this track in: its target when converting, its own otherwise.
  private var outputCodecName: String {
    guard case let .convert(codec, _) = action else { return stream.codecName }
    return String(localized: "→ \(codec)", bundle: #bundle)
  }

  /**
   The shape of what the track carries, in the one measure that distinguishes
   tracks worth telling apart: a frame height for video, a channel layout for
   audio. Subtitles have none.
   */
  private var shape: String? {
    switch stream {
      case let video as VideoStream: video.shapeName
      case let audio as AudioStream: audio.channelLayoutName
      default: nil
    }
  }

  /// The facts particular to the kind of media the track carries.
  private var mediaFacts: [TrackFact] {
    switch stream {
      case let video as VideoStream: video.facts
      case let audio as AudioStream: audio.facts
      default: []
    }
  }

  /**
   The facts the container tags the track with rather than the codec: how
   densely it is encoded, and how a player should treat it.
   */
  private var tagFacts: [TrackFact] {
    let flags = stream.dispositions.displayList
    return [
      stream.bitsPerSecond.map {
        TrackFact(name: String(localized: "Bit rate", bundle: #bundle), value: Self.bitRate($0))
      },
      flags.isEmpty
        ? nil : TrackFact(name: String(localized: "Flags", bundle: #bundle), value: flags)
    ].compactMap(\.self)
  }

  /**
   Foundation has no bit-rate unit to format whole, so the magnitude is
   converted through `UnitInformationStorage` and carries its own "kbps".
   */
  private static func bitRate(_ bitsPerSecond: UInt) -> String {
    let kilobits = Measurement(value: Double(bitsPerSecond), unit: UnitInformationStorage.bits)
      .converted(to: .kilobits)
      .value
    return String(
      localized: "\(kilobits, format: .number.precision(.fractionLength(0))) kbps",
      bundle: #bundle
    )
  }
}

extension VideoStream {

  /**
   The frame as a viewer names it — "1080p", "1080i" — rather than as a pair of
   pixel counts. Height and scan are what distinguish one release from another;
   width follows from the aspect ratio.

   A stream with no `field_order` tag is read as progressive, which is what an
   untagged modern release almost always is.
   */
  fileprivate var shapeName: String {
    let lines = height.formatted(.number.grouping(.never))
    return fieldOrder == nil || fieldOrder == .progressive
      ? String(
        localized: "\(lines)p",
        bundle: #bundle,
        comment: "A progressive frame height, e.g. “1080p”. The argument is the number of lines."
      )
      : String(
        localized: "\(lines)i",
        bundle: #bundle,
        comment: "An interlaced frame height, e.g. “1080i”. The argument is the number of lines."
      )
  }

  fileprivate var facts: [TrackFact] {
    [
      TrackFact(
        name: String(localized: "Dimensions", bundle: #bundle),
        // Grouping separators are for quantities; a frame size reads as a pair
        // of identifiers, and "1,920 × 1,080" looks like a typo.
        value: String(
          localized:
            "\(width, format: .number.grouping(.never)) × \(height, format: .number.grouping(.never))",
          bundle: #bundle
        )
      ),
      pixelFormat.map {
        TrackFact(name: String(localized: "Pixel format", bundle: #bundle), value: $0)
      },
      fieldOrder.map {
        TrackFact(name: String(localized: "Scan", bundle: #bundle), value: $0.displayName)
      }
    ].compactMap(\.self)
  }
}

extension AudioStream {

  /**
   The channel count as a listener names it, which is what tells a main mix
   from the stereo downmix beside it in the same language.
   */
  fileprivate var channelLayoutName: String {
    switch channelCount {
      case 1: String(localized: "Mono", bundle: #bundle)
      case 2: String(localized: "Stereo", bundle: #bundle)
      case 6: "5.1"
      case 8: "7.1"
      default:
        String(
          localized: "\(channelCount, format: .number)ch",
          bundle: #bundle,
          comment: "A channel count with no common name, e.g. “7ch”."
        )
    }
  }

  fileprivate var facts: [TrackFact] {
    [
      TrackFact(
        name: String(localized: "Channels", bundle: #bundle),
        value: String(
          localized: "\(channelCount, format: .number) (\(channelLayoutName))",
          bundle: #bundle,
          comment:
            "An audio channel count and the layout it makes, e.g. “6 (5.1)”. The first argument is the count, the second its name."
        )
      ),
      TrackFact(
        name: String(localized: "Sample rate", bundle: #bundle),
        value: sampleRateDescription
      ),
      bitsPerSample > 0
        ? TrackFact(
          name: String(localized: "Bit depth", bundle: #bundle),
          value: String(localized: "\(bitsPerSample, format: .number)-bit", bundle: #bundle)
        )
        : nil,
      sampleFormat.map {
        TrackFact(name: String(localized: "Sample format", bundle: #bundle), value: $0)
      }
    ].compactMap(\.self)
  }

  private var sampleRateDescription: String {
    Measurement(value: Double(sampleRate), unit: UnitFrequency.hertz)
      .converted(to: .kilohertz)
      .formatted(.measurement(width: .abbreviated, usage: .asProvided))
  }
}

extension VideoStream.FieldOrder {

  /**
   How the scan reads to a viewer: every field order but `progressive`
   describes interlaced video, and which field leads isn't something the user
   can act on.
   */
  fileprivate var displayName: String {
    switch self {
      case .progressive: String(localized: "Progressive", bundle: #bundle)
      case .tt, .bb, .tb, .bt: String(localized: "Interlaced", bundle: #bundle)
    }
  }
}

extension Set<Disposition> {

  /**
   The flags as one phrase, most decisive first. A narrow column truncates, and
   what it truncates away should be what nobody decides a track's fate on —
   which is why this is ranked rather than alphabetical.
   */
  var displayList: String {
    sorted { ($0.decisionRank, $0.displayName) < ($1.decisionRank, $1.displayName) }
      .map(\.displayName)
      .formatted(.list(type: .and))
  }
}

extension Disposition {

  /**
   The flags a keep-or-drop decision actually turns on, in the order they
   matter. Everything absent from this list sorts after all of them.
   */
  private static let decisionOrder: [Self] = [
    .default, .forced, .comment, .hearingImpaired, .visualImpaired, .descriptions, .captions,
    .original, .dub
  ]

  fileprivate var decisionRank: Int {
    Self.decisionOrder.firstIndex(of: self) ?? Self.decisionOrder.count
  }

  /// The flag's name as the inspector lists it.
  var displayName: String {
    switch self {
      case .default: String(localized: "Default", bundle: #bundle)
      case .dub: String(localized: "Dubbed", bundle: #bundle)
      case .original: String(localized: "Original", bundle: #bundle)
      case .comment: String(localized: "Commentary", bundle: #bundle)
      case .lyrics: String(localized: "Lyrics", bundle: #bundle)
      case .karaoke: String(localized: "Karaoke", bundle: #bundle)
      case .forced: String(localized: "Forced", bundle: #bundle)
      case .hearingImpaired: String(localized: "Hearing impaired", bundle: #bundle)
      case .visualImpaired: String(localized: "Visually impaired", bundle: #bundle)
      case .cleanEffects: String(localized: "Clean effects", bundle: #bundle)
      case .attachedPic: String(localized: "Cover art", bundle: #bundle)
      case .timedThumbnails: String(localized: "Timed thumbnails", bundle: #bundle)
      case .nonDiegetic: String(localized: "Non-diegetic", bundle: #bundle)
      case .captions: String(localized: "Captions", bundle: #bundle)
      case .descriptions: String(localized: "Descriptions", bundle: #bundle)
      case .metadata: String(localized: "Metadata", bundle: #bundle)
      case .dependent: String(localized: "Dependent", bundle: #bundle)
      case .stillImage: String(localized: "Still image", bundle: #bundle)
      case .multilayer: String(localized: "Multilayer", bundle: #bundle)
    }
  }
}

#if DEBUG
  /**
   The first track of `type` in the standard preview container, kept. The facts
   grid only reads the stream, so any action that keeps the track will do.
   */
  @MainActor
  private func previewTrack(_ type: StreamOperation.StreamType) -> PlannedTrack {
    PlannedTrack(stream: previewStream(type), type: type, action: .copy)
  }

  @MainActor
  private func previewStream(_ type: StreamOperation.StreamType) -> any CodedStream {
    let container = PreviewSupport.container()
    switch type {
      case .video: return container.videoStreams[0]
      case .audio: return container.audioStreams[0]
      case .subtitle: return container.subtitleStreams[0]
    }
  }

  #Preview("Track facts — video") {
    TrackFactsView(facts: previewTrack(.video).facts)
      .padding()
      .frame(width: 280)
  }

  #Preview("Track facts — audio") {
    TrackFactsView(facts: previewTrack(.audio).facts)
      .padding()
      .frame(width: 280)
  }

  #Preview("Track facts — subtitle") {
    TrackFactsView(facts: previewTrack(.subtitle).facts)
      .padding()
      .frame(width: 280)
  }

  #Preview("Track facts — long title") {
    TrackFactsView(
      facts: previewTrack(.audio).facts + [
        TrackFact(
          name: String(localized: "Title", bundle: #bundle),
          value: "Commentary with the director, the cinematographer, and the second-unit crew"
        )
      ]
    )
    .padding()
    .frame(width: 280)
  }
#endif
