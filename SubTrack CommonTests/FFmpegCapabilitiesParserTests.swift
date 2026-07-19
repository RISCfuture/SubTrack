import Foundation
import Testing

@testable import SubTrack_Common

@Suite
struct FFmpegCapabilitiesParserTests {

  // Trimmed but structurally faithful samples of real `ffmpeg` output.
  private static let versionOutput = """
    ffmpeg version 6.1.1 Copyright (c) 2000-2023 the FFmpeg developers
    built with Apple clang version 15.0.0 (clang-1500.0.40.1)
    configuration: --prefix=/opt --enable-gpl --enable-libx264 --enable-libx265
    libavutil      58. 29.100 / 58. 29.100
    libavcodec     60. 31.102 / 60. 31.102
    libavformat    60. 16.100 / 60. 16.100
    """

  private static let formatsOutput = """
    File formats:
     D. = Demuxing supported
     .E = Muxing supported
     --
     D  3dostr          3DO STR
      E 3g2             3GP2 (3GPP2 file format)
     DE mov,mp4,m4a,3gp,3g2,mj2  QuickTime / MOV
     D  matroska,webm   Matroska / WebM
    """

  private static let fullEncodersOutput = """
    Encoders:
     V..... = Video
     A..... = Audio
     S..... = Subtitle
     ------
     V....D libx264              libx264 H.264 / AVC (codec h264)
     V....D libx265              libx265 H.265 / HEVC (codec hevc)
     V....D hevc_videotoolbox    VideoToolbox H.265 (codec hevc)
     A....D aac                  AAC (Advanced Audio Coding)
     S..... mov_text             3GPP Timed Text subtitle
    """

  private static let lgplEncodersOutput = """
    Encoders:
     V..... = Video
     ------
     V....D hevc_videotoolbox    VideoToolbox H.265 (codec hevc)
     A....D aac                  AAC (Advanced Audio Coding)
    """

  private static let decodersOutput = """
    Decoders:
     V..... = Video
     ------
     V....D h264                 H.264 / AVC / MPEG-4 AVC
     V....D hevc                 H.265 / HEVC
     A....D aac                  AAC (Advanced Audio Coding)
    """

  @Test
  func parsesVersionAndConfiguration() throws {
    let info = try #require(FFmpegOutputParser.parseVersion(Self.versionOutput))
    #expect(info.version == "6.1.1")
    let configuration = try #require(info.configuration)
    #expect(configuration.contains("--enable-libx264"))
    #expect(info.libraryVersions.contains("libavcodec 60.31.102"))
  }

  @Test
  func parsesContainerDirections() throws {
    let containers = FFmpegOutputParser.parseFormats(Self.formatsOutput)
    let mov = try #require(containers.first { $0.name == "mov,mp4,m4a,3gp,3g2,mj2" })
    #expect(mov.canDemux && mov.canMux)
    #expect(mov.summary == "QuickTime / MOV")
    let webm = try #require(containers.first { $0.name == "matroska,webm" })
    #expect(webm.canDemux && !webm.canMux)
  }

  @Test
  func mergesEncodeAndDecodeCapabilities() throws {
    let codecs = FFmpegOutputParser.parseCodecs(
      encoders: Self.fullEncodersOutput,
      decoders: Self.decodersOutput
    )
    // A GPL build advertises libx264/libx265 as encode-only.
    let x264 = try #require(codecs.video.first { $0.name == "libx264" })
    #expect(x264.canEncode && !x264.canDecode)
    // h264 appears only among decoders.
    let h264 = try #require(codecs.video.first { $0.name == "h264" })
    #expect(!h264.canEncode && h264.canDecode)
    // aac is in both lists, so it merges into one entry supporting both.
    let aac = try #require(codecs.audio.first { $0.name == "aac" })
    #expect(aac.canEncode && aac.canDecode)
    #expect(codecs.subtitle.contains { $0.name == "mov_text" })
  }

  @Test
  func lgplBuildHonestlyOmitsX264() {
    let codecs = FFmpegOutputParser.parseCodecs(
      encoders: Self.lgplEncodersOutput,
      decoders: Self.decodersOutput
    )
    #expect(!codecs.video.contains { $0.name == "libx264" })
    #expect(!codecs.video.contains { $0.name == "libx265" })
    #expect(codecs.video.contains { $0.name == "hevc_videotoolbox" })
  }
}
