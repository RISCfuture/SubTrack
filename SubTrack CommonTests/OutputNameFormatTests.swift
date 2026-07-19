import Foundation
import Testing

import SubTrack_Common

@Suite
struct OutputNameFormatTests {
  private let showA = URL(filePath: "/Movies/A/Show.mkv")
  private let showB = URL(filePath: "/Movies/B/Show.mkv")
  private let destination = URL(filePath: "/Output")

  // MARK: - Parsing

  @Test
  func parsesTextAndTokens() {
    #expect(OutputNameFormat.slimmed.segments == [.token(.originalName), .text(" (slimmed)")])
  }

  @Test
  func readsDoubledBracesAsLiteralBraces() {
    #expect(OutputNameFormat(template: "{{name}}").segments == [.text("{name}")])
  }

  @Test
  func readsAnUnrecognizedPlaceholderAsText() {
    #expect(
      OutputNameFormat(template: "{foo} {n}").segments == [.text("{foo} "), .token(.sequenceNumber)]
    )
  }

  @Test
  func roundTripsSegmentsThroughATemplate() {
    let segments: [OutputNameSegment] = [
      .text("A {literal} "), .token(.originalName), .text(" #"), .token(.sequenceNumber)
    ]
    #expect(OutputNameFormat(segments: segments).segments == segments)
  }

  // MARK: - Rendering

  @Test
  func rendersTokensAndKeepsTheSourceExtension() {
    let format = OutputNameFormat(template: "{n} - {name} (slim)")
    #expect(format.fileName(for: showA, position: 3) == "3 - Show (slim).mkv")
  }

  @Test
  func replacesPathSeparators() {
    let format = OutputNameFormat(template: "{name}/2: HD")
    #expect(format.fileName(for: showA, position: 1) == "Show-2- HD.mkv")
  }

  @Test
  func trimsLeadingAndTrailingDotsAndWhitespace() {
    #expect(
      OutputNameFormat(template: " .{name}. ").fileName(for: showA, position: 1) == "Show.mkv"
    )
  }

  @Test
  func fallsBackToTheSourceNameWhenTheFormatRendersNothing() {
    #expect(OutputNameFormat(template: "  ").fileName(for: showA, position: 1) == "Show.mkv")
  }

  @Test
  func addsNoExtensionWhenTheSourceHasNone() {
    let source = URL(filePath: "/Movies/Show")
    #expect(OutputNameFormat.slimmed.fileName(for: source, position: 1) == "Show (slimmed)")
  }

  // MARK: - Custom names

  @Test
  func keepsTheSourceExtensionOnACustomName() {
    #expect(
      OutputNameFormat.fileName(customBase: "Director’s Cut", for: showA)
        == "Director’s Cut.mkv"
    )
  }

  @Test
  func sanitizesACustomName() {
    #expect(OutputNameFormat.fileName(customBase: " .Show/2: HD. ", for: showA) == "Show-2- HD.mkv")
  }

  @Test
  func fallsBackToTheSourceNameWhenACustomNameIsBlank() {
    #expect(OutputNameFormat.fileName(customBase: "  ", for: showA) == "Show.mkv")
  }

  @Test
  func writesACustomNameIntoTheDestination() {
    #expect(
      OutputNameFormat.outputURL(customBase: "Cut", for: showA, in: destination)
        == URL(filePath: "/Output/Cut.mkv")
    )
  }

  // MARK: - Conflicts

  @Test
  func flagsTwoSourcesThatWouldShareOneOutput() {
    let conflicts = OutputNameFormat.slimmed.conflicts(naming: [showA, showB], into: destination)
    #expect(conflicts == [.duplicateOutputs(name: "Show (slimmed).mkv", sources: [showA, showB])])
  }

  @Test
  func acceptsSameNamedSourcesSavedBesideThemselves() {
    #expect(OutputNameFormat.slimmed.conflicts(naming: [showA, showB], into: nil).isEmpty)
  }

  @Test
  func resolvesDuplicatesWithTheSequenceToken() {
    let format = OutputNameFormat(template: "{name} {n}")
    #expect(format.conflicts(naming: [showA, showB], into: destination).isEmpty)
  }

  @Test
  func flagsAnOutputThatWouldOverwriteItsOwnSource() {
    let format = OutputNameFormat(template: "{name}")
    #expect(format.conflicts(naming: [showA], into: nil) == [.overwritesSource(sources: [showA])])
  }
}
