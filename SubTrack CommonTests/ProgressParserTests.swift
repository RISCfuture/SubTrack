import Foundation
import Testing

@testable import SubTrack_Common

@Suite
struct ProgressParserTests {

  @Test
  func `emits nothing until block completes`() {
    var parser = ProgressParser(totalDuration: .seconds(100))
    #expect(parser.consume(line: "frame=10") == nil)
    #expect(parser.consume(line: "out_time_us=5000000") == nil)
  }

  @Test
  func `computes fraction from microseconds`() throws {
    var parser = ProgressParser(totalDuration: .seconds(100))
    _ = parser.consume(line: "out_time_us=25000000")
    let block = parser.consume(line: "progress=continue")
    let progress = try #require(block)
    #expect(progress.fraction == 0.25)
    #expect(abs(progress.outTime.seconds - 25) < 0.001)
  }

  @Test
  func `parses speed and total size`() throws {
    var parser = ProgressParser(totalDuration: .seconds(100))
    _ = parser.consume(line: "total_size=1048576")
    _ = parser.consume(line: "speed=2.5x")
    _ = parser.consume(line: "out_time_us=10000000")
    let block = parser.consume(line: "progress=continue")
    let progress = try #require(block)
    #expect(progress.totalSize == 1_048_576)
    #expect(progress.speed == 2.5)
  }

  @Test
  func `end block reports complete`() throws {
    var parser = ProgressParser(totalDuration: .seconds(100))
    _ = parser.consume(line: "out_time_us=99000000")
    let block = parser.consume(line: "progress=end")
    let progress = try #require(block)
    #expect(progress.fraction == 1)
  }

  @Test
  func `unknown duration yields indeterminate fraction`() throws {
    var parser = ProgressParser(totalDuration: .zero)
    _ = parser.consume(line: "out_time_us=5000000")
    let block = parser.consume(line: "progress=continue")
    let progress = try #require(block)
    #expect(progress.fraction == nil)
  }

  @Test
  func `falls back to formatted timestamp`() throws {
    var parser = ProgressParser(totalDuration: .seconds(3600))
    _ = parser.consume(line: "out_time=00:30:00.000000")
    let block = parser.consume(line: "progress=continue")
    let progress = try #require(block)
    #expect(progress.fraction == 0.5)
  }

  @Test
  func `clamps overshoot to one`() throws {
    var parser = ProgressParser(totalDuration: .seconds(10))
    _ = parser.consume(line: "out_time_us=15000000")
    let block = parser.consume(line: "progress=continue")
    let progress = try #require(block)
    #expect(progress.fraction == 1)
  }
}

@Suite
struct TrackSelectionTests {

  /**
   A container with one video track and two audio tracks, English then French,
   so English-only rules keep one of the pair and drop the other.
   */
  private func engAndFraAudioContainer() throws -> Container {
    try JSONDecoder().decode(
      Container.self,
      from: Data(
        """
        {
          "streams": [
            {"index":0,"codec_name":"hevc","codec_type":"video","width":1920,"height":1080,
             "disposition":{"default":1},"tags":{"language":"eng"}},
            {"index":1,"codec_name":"aac","codec_type":"audio","sample_rate":"48000","channels":2,
             "bits_per_sample":0,"disposition":{"default":1},"tags":{"language":"eng"}},
            {"index":2,"codec_name":"aac","codec_type":"audio","sample_rate":"48000","channels":2,
             "bits_per_sample":0,"disposition":{"default":1},"tags":{"language":"fra"}}
          ],
          "format":{"filename":"/m.mkv","duration":"60.0","size":"1000"}
        }
        """.utf8
      )
    )
  }

  @Test
  func `seeds all tracks with rule outcomes`() throws {
    let container = try engAndFraAudioContainer()
    let operations = try SlimRules(languages: ["eng"]).makeConverter(container: container)
      .operations()
    let selection = FileTrackSelection.seed(container: container, operations: operations)

    #expect(selection.choices.count == 3)
    // The French audio (index 2) is not kept by the eng-only rules.
    let french = try #require(selection.choices.first { $0.streamIndex == 2 })
    #expect(french.action == .drop)
    // The kept operations round-trip back out of the selection.
    #expect(selection.operations().count == operations.count)
  }

  @Test
  func `VideoToolbox-only builds omit software encoders`() {
    let full = FileTrackSelection.availableTargets(for: .video, capabilities: .full).map(\.codec)
    #expect(full.contains("libx265"))
    #expect(full.contains("libx264"))

    // A VideoToolbox-only build offers only its hardware encoders, not x264/x265.
    let limited = FileTrackSelection.availableTargets(for: .video, capabilities: .videoToolboxOnly)
      .map(\.codec)
    #expect(limited == ["hevc_videotoolbox", "h264_videotoolbox"])

    // The same gating drops royalty-encumbered audio encoders on limited builds.
    let limitedAudio = FileTrackSelection.availableTargets(
      for: .audio,
      capabilities: .videoToolboxOnly
    )
    .map(\.codec)
    #expect(!limitedAudio.contains("truehd"))
    #expect(!limitedAudio.contains("dts"))
    #expect(limitedAudio.contains("aac"))
  }

  @Test
  func `probed targets are every encoder the build reports`() {
    let capabilities = FFmpegCapabilities(
      version: nil,
      containers: [],
      videoCodecs: [
        FFmpegCodec(
          name: "libx264",
          summary: "libx264 H.264 / AVC (codec h264)",
          mediaType: .video,
          canEncode: true,
          canDecode: false
        ),
        FFmpegCodec(
          name: "av1",
          summary: "Alliance for Open Media AV1",
          mediaType: .video,
          canEncode: false,
          canDecode: true
        )
      ],
      audioCodecs: [],
      subtitleCodecs: []
    )
    let targets = FileTrackSelection.availableTargets(for: .video, capabilities: capabilities)

    // The codec family comes first, then the encoder; the decode-only codec is
    // not a transcode target at all.
    #expect(targets.map(\.codec) == ["h264", "libx264"])
    // Neither the encoder's own name nor its family is repeated back in the
    // description — the target already carries both.
    #expect(targets[1].summary == "H.264 / AVC")
  }
}
