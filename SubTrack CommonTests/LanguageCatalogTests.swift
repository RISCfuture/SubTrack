import Foundation
import Testing

@testable import SubTrack_Common

@Suite
struct LanguageCatalogTests {

  @Test
  func `catalog is non-empty, deduplicated, and sorted`() {
    let all = LanguageCatalog.all
    #expect(!all.isEmpty)

    let codes = all.map(\.code)
    #expect(Set(codes).count == codes.count, "codes should be de-duplicated")
    #expect(all.allSatisfy { $0.code.count == 3 }, "codes should be ISO 639-2 alpha-3")

    let names = all.map(\.name)
    let sorted = names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    #expect(names == sorted, "entries should be sorted by localized name")
  }

  @Test
  func `resolves known codes case-insensitively and rejects unknown`() {
    #expect(LanguageCatalog.name(for: "eng") != nil)
    #expect(LanguageCatalog.name(for: "jpn") != nil)
    #expect(LanguageCatalog.name(for: "ENG") == LanguageCatalog.name(for: "eng"))
    #expect(LanguageCatalog.name(for: "zzzz") == nil)
  }

  /**
   The bibliographic ISO 639-2 codes Matroska and `ffmpeg` tag tracks with:
   only the terminological form has an alpha-3 identifier for the catalog to
   be built from, so these resolve through the fallback or not at all.
   */
  @Test(arguments: [("fre", "fra"), ("ger", "deu"), ("dut", "nld"), ("chi", "zho")])
  func `names bibliographic codes like their terminological twin`(
    bibliographic: String,
    terminological: String
  ) {
    #expect(LanguageCatalog.name(for: bibliographic) == LanguageCatalog.name(for: terminological))
    #expect(LanguageCatalog.name(for: bibliographic) != nil)
  }
}
