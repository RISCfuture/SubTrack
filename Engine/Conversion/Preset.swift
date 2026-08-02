import Foundation

/**
 A named bundle of keep-``SlimRules`` and the ``OutputNameFormat`` its output
 is named by — the HandBrake-style preset.
 */
public struct Preset: Identifiable, Sendable, Equatable, Codable {

  /**
   Video codecs a web download already uses, listed ahead of the disc codecs
   so a VP9 or AV1 source is copied rather than re-encoded.
   */
  private static let webVideoCodecs = ["vp9", "av1", "hevc", "h264"]

  /**
   Audio codecs a web download already uses. Opus leads because it is what
   YouTube ships; re-encoding it to a disc codec makes the track bigger for
   no gain when the source was never going to a receiver.
   */
  private static let webAudioCodecs = ["opus", "aac", "eac3", "ac3", "flac"]

  /**
   The presets a fresh install starts with. They are seeded once into an empty
   store and are ordinary presets from that moment on — the app neither
   protects nor restores them, so editing or deleting one sticks. Their IDs are
   stable so the seeding never doubles up.

   They are grouped by where the file came from, because that is what decides
   which codecs are worth keeping: a disc rip carries the lossless Dolby and
   DTS tracks a receiver wants, while a web download carries Opus and VP9,
   which only lose size and quality by being converted into disc codecs.
   */
  public static let starters: [Self] = [
    Self(
      id: UUID(uuidString: "00000000-0000-0000-0000-0000000000E1")!,
      name: String(localized: "Blu-ray Rip — English Only", bundle: #bundle),
      rules: SlimRules(languages: ["eng"])
    ),
    Self(
      id: UUID(uuidString: "00000000-0000-0000-0000-0000000000E2")!,
      name: String(localized: "Blu-ray Rip — English + Commentary", bundle: #bundle),
      rules: SlimRules(languages: ["eng"], includeOtherAudio: true)
    ),
    Self(
      id: UUID(uuidString: "00000000-0000-0000-0000-0000000000E4")!,
      name: String(localized: "Blu-ray Rip — Keep Untagged Tracks", bundle: #bundle),
      rules: SlimRules(languages: ["eng"], preserveNoLanguages: true, includeOtherAudio: true)
    ),
    Self(
      id: UUID(uuidString: "00000000-0000-0000-0000-0000000000E5")!,
      name: String(localized: "Web / YouTube Rip — English Only", bundle: #bundle),
      rules: SlimRules(
        languages: ["eng"],
        // A YouTube download often tags no language at all, and dropping the
        // only audio track it has would leave the output silent.
        preserveNoLanguages: true,
        videoPreferredCodecs: webVideoCodecs,
        audioPreferredCodecs: webAudioCodecs
      )
    ),
    Self(
      id: UUID(uuidString: "00000000-0000-0000-0000-0000000000E6")!,
      name: String(localized: "Streaming Service Rip — English Only", bundle: #bundle),
      rules: SlimRules(
        languages: ["eng"],
        // Service rips carry many languages and tag them inconsistently, so an
        // untagged track is more often the wanted one than a stray.
        preserveNoLanguages: true
      )
    )
  ]

  /// Identifies the preset for as long as it is stored.
  public let id: UUID

  /// The name the preset is listed under.
  public var name: String

  /// The keep-rules the preset applies to each file.
  public var rules: SlimRules

  /// How the preset names the files it produces.
  public var naming: OutputNameFormat

  /**
   Creates a preset.

   - Parameter id: Identifies the preset for as long as it is stored.
   - Parameter name: The name the preset is listed under.
   - Parameter rules: The keep-rules the preset applies to each file.
   - Parameter naming: How the preset names the files it produces.
   */
  public init(
    id: UUID,
    name: String,
    rules: SlimRules,
    naming: OutputNameFormat = .slimmed
  ) {
    self.id = id
    self.name = name
    self.rules = rules
    self.naming = naming
  }
}
