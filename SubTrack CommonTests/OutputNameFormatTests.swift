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
  func `parses text and tokens`() {
    #expect(OutputNameFormat.slimmed.segments == [.token(.originalName), .text(" (slimmed)")])
  }

  @Test
  func `reads doubled braces as literal braces`() {
    #expect(OutputNameFormat(template: "{{name}}").segments == [.text("{name}")])
  }

  @Test
  func `reads an unrecognized placeholder as text`() {
    #expect(
      OutputNameFormat(template: "{foo} {n}").segments == [.text("{foo} "), .token(.sequenceNumber)]
    )
  }

  @Test
  func `round-trips segments through a template`() {
    let segments: [OutputNameSegment] = [
      .text("A {literal} "), .token(.originalName), .text(" #"), .token(.sequenceNumber)
    ]
    #expect(OutputNameFormat(segments: segments).segments == segments)
  }

  // MARK: - Rendering

  @Test
  func `renders tokens and keeps the source extension`() {
    let format = OutputNameFormat(template: "{n} - {name} (slim)")
    #expect(format.fileName(for: showA, position: 3) == "3 - Show (slim).mkv")
  }

  @Test
  func `replaces path separators`() {
    let format = OutputNameFormat(template: "{name}/2: HD")
    #expect(format.fileName(for: showA, position: 1) == "Show-2- HD.mkv")
  }

  @Test
  func `trims leading and trailing dots and whitespace`() {
    #expect(
      OutputNameFormat(template: " .{name}. ").fileName(for: showA, position: 1) == "Show.mkv"
    )
  }

  @Test
  func `falls back to the source name when the format renders nothing`() {
    #expect(OutputNameFormat(template: "  ").fileName(for: showA, position: 1) == "Show.mkv")
  }

  @Test
  func `adds no extension when the source has none`() {
    let source = URL(filePath: "/Movies/Show")
    #expect(OutputNameFormat.slimmed.fileName(for: source, position: 1) == "Show (slimmed)")
  }

  // MARK: - Custom names

  @Test
  func `keeps the source extension on a custom name`() {
    #expect(
      OutputNameFormat.fileName(customBase: "Director’s Cut", for: showA)
        == "Director’s Cut.mkv"
    )
  }

  @Test
  func `sanitizes a custom name`() {
    #expect(OutputNameFormat.fileName(customBase: " .Show/2: HD. ", for: showA) == "Show-2- HD.mkv")
  }

  @Test
  func `falls back to the source name when a custom name is blank`() {
    #expect(OutputNameFormat.fileName(customBase: "  ", for: showA) == "Show.mkv")
  }

  @Test
  func `writes a custom name into the destination`() {
    #expect(
      OutputNameFormat.outputURL(customBase: "Cut", for: showA, in: destination)
        == URL(filePath: "/Output/Cut.mkv")
    )
  }

  // MARK: - Conflicts

  @Test
  func `flags two sources that would share one output`() {
    let conflicts = OutputNameFormat.slimmed.conflicts(naming: [showA, showB], into: destination)
    #expect(conflicts == [.duplicateOutputs(name: "Show (slimmed).mkv", sources: [showA, showB])])
  }

  @Test
  func `accepts same-named sources saved beside themselves`() {
    #expect(OutputNameFormat.slimmed.conflicts(naming: [showA, showB], into: nil).isEmpty)
  }

  @Test
  func `resolves duplicates with the sequence token`() {
    let format = OutputNameFormat(template: "{name} {n}")
    #expect(format.conflicts(naming: [showA, showB], into: destination).isEmpty)
  }

  @Test
  func `flags an output that would overwrite its own source`() {
    let format = OutputNameFormat(template: "{name}")
    #expect(format.conflicts(naming: [showA], into: nil) == [.overwritesSource(sources: [showA])])
  }
}
