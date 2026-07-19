import Foundation

/**
 The localized catalog of languages the user can choose to keep.

 Built from the OS/CLDR data rather than a bundled table: `Locale` already
 localizes the ISO 639-2 three-letter codes that `ffmpeg`/Matroska tag tracks
 with (`"jpn"` → "Japanese"), localized to the user's UI language. A static
 database would only duplicate this and go stale.
 */
enum LanguageCatalog {

  /**
   Every named language, de-duplicated by alpha-3 code and sorted by localized
   name.
   */
  static let all: [Language] = build()

  private static let byCode: [String: Language] = Dictionary(
    all.map { ($0.code, $0) },
    uniquingKeysWith: { first, _ in first }
  )

  /**
   The localized name for a code, or `nil` when CLDR has no name for it — which
   drives the "unrecognized language" warning in the editor.

   Falls back to naming the code directly when it isn't one of the ``all``
   entries: ISO 639-2 gives about twenty languages a second, *bibliographic*
   code (`fre`, `ger`, `dut`, `chi`…), and Matroska and `ffmpeg` tag tracks
   with either. Only the terminological form (`fra`, `deu`, `nld`, `zho`) has
   an alpha-3 identifier for ``all`` to be built from, so the bibliographic
   ones reach us unnamed even though CLDR knows them perfectly well.
   */
  static func name(for code: String) -> String? {
    let code = normalized(code)
    return byCode[code]?.name ?? Locale.current.localizedString(forLanguageCode: code)
  }

  private static func build() -> [Language] {
    let locale = Locale.current
    var seen = Set<String>()
    var languages = [Language]()
    for languageCode in Locale.LanguageCode.isoLanguageCodes {
      guard let code = alpha3(for: languageCode),
        let name = locale.localizedString(forLanguageCode: code),
        seen.insert(code).inserted
      else { continue }
      languages.append(Language(code: code, name: name))
    }
    return languages.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }

  /**
   The three-letter (alpha-3) form `ffmpeg` uses, derived from any 2- or
   3-letter code, or `nil` when no alpha-3 form exists.
   */
  private static func alpha3(for languageCode: Locale.LanguageCode) -> String? {
    if let viaStandard = languageCode.identifier(.alpha3), viaStandard.count == 3 {
      return viaStandard
    }
    if languageCode.identifier.count == 3 { return languageCode.identifier }
    return nil
  }

  private static func normalized(_ code: String) -> String {
    code.trimmingCharacters(in: .whitespaces).lowercased()
  }

  /**
   One selectable language: the three-letter (ISO 639-2 alpha-3) code stored
   in the rules, and its name localized to the user's UI language.
   */
  struct Language: Identifiable, Hashable {
    let code: String
    let name: String
    var id: String { code }
  }
}
