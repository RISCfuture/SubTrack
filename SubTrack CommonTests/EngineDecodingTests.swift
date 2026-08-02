import Foundation
import Testing

@testable import SubTrack_Common

/**
 A representative `ffprobe -print_format json -show_format -show_streams`
 payload: an HEVC video, two audio tracks (one default AAC, one DTS with a
 raw-sample bit depth), a SubRip subtitle, and a data stream that must be
 dropped.
 */
private let sampleProbeJSON = """
  {
    "streams": [
      {"index":0,"codec_name":"hevc","codec_type":"video","width":1920,"height":1080,
       "pix_fmt":"yuv420p10le","profile":"Main 10","field_order":"progressive",
       "disposition":{"default":1},"tags":{"language":"eng","title":"Feature"}},
      {"index":1,"codec_name":"aac","codec_type":"audio","sample_rate":"48000","channels":6,
       \
  "bits_per_sample":0,"disposition":{"default":1},"tags":{"language":"eng","title":"Surround"}},
      {"index":2,"codec_name":"dts","codec_type":"audio","sample_rate":"48000","channels":8,
       "bits_per_sample":0,"bits_per_raw_sample":"24","disposition":{"default":0},
       "tags":{"language":"jpn"}},
      {"index":3,"codec_name":"subrip","codec_type":"subtitle","disposition":{"default":0},
       "tags":{"language":"eng"}},
      {"index":4,"codec_type":"data","disposition":{}}
    ],
    "format":{"filename":"/movies/Ep01.mkv","duration":"1415.123000","size":"1503238553",
              "tags":{"title":"Episode 1"}}
  }
  """

private func decodeContainer(_ json: String) throws -> Container {
  try JSONDecoder().decode(Container.self, from: Data(json.utf8))
}

@Suite
struct ContainerDecodingTests {

  @Test
  func decodesFormatMetadata() throws {
    let container = try decodeContainer(sampleProbeJSON)
    #expect(container.filename == "/movies/Ep01.mkv")
    #expect(abs(container.durationSec - 1415.123) < 0.001)
    #expect(container.size == 1_503_238_553)
    #expect(container.tags["title"] == "Episode 1")
  }

  @Test
  func partitionsStreamsByTypeAndDropsData() throws {
    let container = try decodeContainer(sampleProbeJSON)
    // The data stream is decoded but not retained.
    #expect(container.streams.count == 4)
    #expect(container.videoStreams.count == 1)
    #expect(container.audioStreams.count == 2)
    #expect(container.subtitleStreams.count == 1)
  }

  @Test
  func decodesStreamDetails() throws {
    let container = try decodeContainer(sampleProbeJSON)

    let video = try #require(container.videoStreams.first)
    #expect(video.codecName == "hevc")
    #expect(video.width == 1920 && video.height == 1080)
    #expect(video.language == "eng")
    #expect(video.fieldOrder == .progressive)

    let dts = try #require(container.audioStreams.first { $0.codecName == "dts" })
    #expect(dts.channelCount == 8)
    // bits_per_sample was 0, so the decoder falls back to bits_per_raw_sample.
    #expect(dts.bitsPerSample == 24)
    #expect(dts.language == "jpn")
  }
}

@Suite
struct ConverterTests {

  /**
   A minimal container whose sole video stream uses a codec outside the
   preferred list, forcing a transcode operation.
   */
  private func containerNeedingVideoTranscode() throws -> Container {
    try decodeContainer(
      """
      {
        "streams": [
          {"index":0,"codec_name":"mpeg2video","codec_type":"video","width":720,"height":480,
           "disposition":{"default":1},"tags":{"language":"eng"}}
        ],
        "format":{"filename":"/movies/old.mkv","duration":"60.0","size":"1000"}
      }
      """
    )
  }

  @Test
  func copiesPreferredStreams() throws {
    let container = try decodeContainer(sampleProbeJSON)
    let converter = Converter(container: container, languages: ["eng"])
    let operations = try converter.operations()
    // hevc video + default eng aac audio + eng subrip subtitle, all preferred → copy.
    #expect(operations.allSatisfy { $0.kind == .copy })
    #expect(operations.contains { $0.streamType == .video })
  }

  /**
   The emitted encoder is the configured `videoConversionCodec`, not the first
   preferred (decode-side) codec.
   */
  @Test
  func transcodesToConfiguredConversionCodec() throws {
    let converter = Converter(container: try containerNeedingVideoTranscode(), languages: ["eng"])
    converter.videoConversionCodec = "hevc_videotoolbox"
    converter.videoConversionOptions = ["-q:v", "60"]

    let operation = try #require(try converter.operations().first)
    #expect(operation.kind == .convert(codec: "hevc_videotoolbox", arguments: ["-q:v", "60"]))
    #expect(
      operation.codecArgument(outputIndex: 0) == ["-c:v:0", "hevc_videotoolbox", "-q:v", "60"]
    )
  }

  /**
   A foreign-first container: audio and subtitles are ordered Russian, then
   English, then French. The rules keep only French then English.
   */
  private func foreignFirstContainer() throws -> Container {
    try decodeContainer(
      """
      {
        "streams": [
          {"index":0,"codec_name":"hevc","codec_type":"video","width":1920,"height":1080,
           "disposition":{"default":1},"tags":{"language":"eng"}},
          {"index":1,"codec_name":"ac3","codec_type":"audio","sample_rate":"48000","channels":6,
           "bits_per_sample":0,"disposition":{"default":1},"tags":{"language":"rus"}},
          {"index":2,"codec_name":"ac3","codec_type":"audio","sample_rate":"48000","channels":6,
           "bits_per_sample":0,"disposition":{"default":0},"tags":{"language":"eng"}},
          {"index":3,"codec_name":"ac3","codec_type":"audio","sample_rate":"48000","channels":6,
           "bits_per_sample":0,"disposition":{"default":0},"tags":{"language":"fra"}},
          {"index":4,"codec_name":"subrip","codec_type":"subtitle","disposition":{"default":0},
           "tags":{"language":"rus"}},
          {"index":5,"codec_name":"subrip","codec_type":"subtitle","disposition":{"default":0},
           "tags":{"language":"eng"}},
          {"index":6,"codec_name":"subrip","codec_type":"subtitle","disposition":{"default":0},
           "tags":{"language":"fra"}}
        ],
        "format":{"filename":"/movies/foreign.mkv","duration":"60.0","size":"1000"}
      }
      """
    )
  }

  /**
   Both audio and subtitle tracks come out in the language-priority order, and
   languages not in the list are dropped.
   */
  @Test
  func ordersTracksByLanguagePriority() throws {
    let converter = Converter(container: try foreignFirstContainer(), languages: ["fra", "eng"])
    let operations = try converter.operations()

    let audioIndexes = operations.filter { $0.streamType == .audio }.map(\.streamIndex)
    let subtitleIndexes = operations.filter { $0.streamType == .subtitle }.map(\.streamIndex)
    #expect(audioIndexes == [3, 2])  // fra, then eng — Russian (1) dropped
    #expect(subtitleIndexes == [6, 5])  // fra, then eng — Russian (4) dropped
  }

  /**
   Seeding a per-file selection preserves the operations' priority order:
   kept tracks first in output order, dropped tracks after in file order.
   */
  @Test
  func seededSelectionPreservesOutputOrder() throws {
    let container = try foreignFirstContainer()
    let operations = try Converter(container: container, languages: ["fra", "eng"]).operations()
    let selection = FileTrackSelection.seed(container: container, operations: operations)

    let audio = selection.choices.filter { $0.streamType == .audio }
    #expect(audio.map(\.streamIndex) == [3, 2, 1])  // kept fra, eng; then dropped rus
    #expect(audio.last?.action == .drop)
    // The kept tracks lead the file's stream operations, in priority order.
    #expect(selection.operations().filter { $0.streamType == .audio }.map(\.streamIndex) == [3, 2])
  }
}

@Suite
struct CodecArgumentTests {

  /**
   Each kept track is numbered against the output's streams of its own type, so
   a plan that copies one audio track and converts another says so per track. A
   per-type `-c:a` would emit both `copy` and the target codec, and FFMPEG would
   apply only the last of them — to both tracks.
   */
  @Test
  func numbersEachTrackWithinItsOwnType() {
    let operations = [
      StreamOperation(streamIndex: 0, streamType: .video, kind: .copy),
      StreamOperation(streamIndex: 3, streamType: .audio, kind: .copy),
      StreamOperation(
        streamIndex: 2,
        streamType: .audio,
        kind: .convert(codec: "eac3", arguments: [])
      ),
      StreamOperation(streamIndex: 6, streamType: .subtitle, kind: .copy)
    ]
    #expect(
      ProgressReportingProcessor.codecArguments(for: operations) == [
        "-c:v:0", "copy",
        "-c:a:0", "copy",
        "-c:a:1", "eac3",
        "-c:s:0", "copy"
      ]
    )
  }
}

@Suite
struct DispositionArgumentTests {

  /**
   The first kept audio track is flagged the container default; the rest are
   cleared. Video and subtitle operations contribute no disposition flags.
   */
  @Test
  func flagsFirstAudioAsDefault() {
    let operations = [
      StreamOperation(streamIndex: 0, streamType: .video, kind: .copy),
      StreamOperation(streamIndex: 3, streamType: .audio, kind: .copy),
      StreamOperation(streamIndex: 2, streamType: .audio, kind: .copy),
      StreamOperation(streamIndex: 6, streamType: .subtitle, kind: .copy)
    ]
    #expect(
      ProgressReportingProcessor.dispositionArguments(for: operations)
        == ["-disposition:a:0", "default", "-disposition:a:1", "0"]
    )
  }

  @Test
  func emitsNothingWithoutAudio() {
    let operations = [StreamOperation(streamIndex: 0, streamType: .video, kind: .copy)]
    #expect(ProgressReportingProcessor.dispositionArguments(for: operations).isEmpty)
  }
}
