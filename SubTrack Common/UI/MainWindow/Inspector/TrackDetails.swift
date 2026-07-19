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
    return isIncluded ? described : String(localized: "\(described) (skipped)")
  }

  /**
   Everything the probe knows about this track, in the order the tab lists it:
   what it is, how it is tagged, and what shape its media takes.
   */
  var facts: [TrackFact] {
    [
      TrackFact(name: String(localized: "Type"), value: typeName),
      TrackFact(name: String(localized: "Codec"), value: codecDescription),
      TrackFact(name: String(localized: "Language"), value: languageName),
      stream.title.map { TrackFact(name: String(localized: "Title"), value: $0) }
    ].compactMap(\.self) + mediaFacts + tagFacts
  }

  private var index: UInt { stream.index }

  private var typeName: String {
    switch type {
      case .video: String(localized: "Video")
      case .audio: String(localized: "Audio")
      case .subtitle: String(localized: "Subtitle")
    }
  }

  /**
   The codec, qualified by its encoding profile when the probe reported one
   (e.g. "h264 (High)").
   */
  private var codecDescription: String {
    guard let profile else { return stream.codecName }
    return String(localized: "\(stream.codecName) (\(profile))")
  }

  private var profile: String? {
    switch stream {
      case let video as VideoStream: video.profile
      case let audio as AudioStream: audio.profile
      default: nil
    }
  }

  /**
   The track's language named in the user's own language, falling back to the
   raw tag when the catalog doesn't recognize it.
   */
  private var languageName: String {
    guard let language = stream.language else { return String(localized: "Untagged") }
    return LanguageCatalog.name(for: language) ?? language
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
    let flags = stream.dispositions
      .map(\.displayName)
      .sorted()
      .formatted(.list(type: .and))
    return [
      stream.bitsPerSecond.map {
        TrackFact(name: String(localized: "Bit rate"), value: Self.bitRate($0))
      },
      flags.isEmpty ? nil : TrackFact(name: String(localized: "Flags"), value: flags)
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
    return String(localized: "\(kilobits, format: .number.precision(.fractionLength(0))) kbps")
  }
}

extension VideoStream {
  fileprivate var facts: [TrackFact] {
    [
      TrackFact(
        name: String(localized: "Dimensions"),
        // Grouping separators are for quantities; a frame size reads as a pair
        // of identifiers, and "1,920 × 1,080" looks like a typo.
        value: String(
          localized:
            "\(width, format: .number.grouping(.never)) × \(height, format: .number.grouping(.never))"
        )
      ),
      pixelFormat.map { TrackFact(name: String(localized: "Pixel format"), value: $0) },
      fieldOrder.map { TrackFact(name: String(localized: "Scan"), value: $0.displayName) }
    ].compactMap(\.self)
  }
}

extension AudioStream {
  fileprivate var facts: [TrackFact] {
    [
      TrackFact(
        name: String(localized: "Channels"),
        value: channelCount.formatted(.number)
      ),
      TrackFact(name: String(localized: "Sample rate"), value: sampleRateDescription),
      bitsPerSample > 0
        ? TrackFact(
          name: String(localized: "Bit depth"),
          value: String(localized: "\(bitsPerSample, format: .number)-bit")
        )
        : nil
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
      case .progressive: String(localized: "Progressive")
      case .tt, .bb, .tb, .bt: String(localized: "Interlaced")
    }
  }
}

extension Disposition {

  /// The flag's name as the inspector lists it.
  fileprivate var displayName: String {
    switch self {
      case .default: String(localized: "Default")
      case .dub: String(localized: "Dubbed")
      case .original: String(localized: "Original")
      case .comment: String(localized: "Commentary")
      case .lyrics: String(localized: "Lyrics")
      case .karaoke: String(localized: "Karaoke")
      case .forced: String(localized: "Forced")
      case .hearingImpaired: String(localized: "Hearing impaired")
      case .visualImpaired: String(localized: "Visually impaired")
      case .cleanEffects: String(localized: "Clean effects")
      case .attachedPic: String(localized: "Cover art")
      case .timedThumbnails: String(localized: "Timed thumbnails")
      case .nonDiegetic: String(localized: "Non-diegetic")
      case .captions: String(localized: "Captions")
      case .descriptions: String(localized: "Descriptions")
      case .metadata: String(localized: "Metadata")
      case .dependent: String(localized: "Dependent")
      case .stillImage: String(localized: "Still image")
      case .multilayer: String(localized: "Multilayer")
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
          name: String(localized: "Title"),
          value: "Commentary with the director, the cinematographer, and the second-unit crew"
        )
      ]
    )
    .padding()
    .frame(width: 280)
  }
#endif
