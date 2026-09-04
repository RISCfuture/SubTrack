import Testing

import SubTrack_Common

@Suite
struct EncoderCapabilitiesTests {

  private func convert(_ codec: String, _ type: StreamOperation.StreamType) -> StreamOperation {
    StreamOperation(streamIndex: 0, streamType: type, kind: .convert(codec: codec, arguments: []))
  }

  @Test
  func `flags unsupported video transcode but not copy`() {
    let operations = [
      StreamOperation(streamIndex: 0, streamType: .video, kind: .copy),
      convert("libx265", .video)
    ]

    let flagged = EncoderCapabilities.videoToolboxOnly.firstUnsupported(in: operations)
    #expect(flagged?.0 == .video)
    #expect(flagged?.1 == "libx265")

    #expect(EncoderCapabilities.full.firstUnsupported(in: operations) == nil)
  }

  @Test
  func `subtitle transcodes are always allowed`() {
    #expect(
      EncoderCapabilities.videoToolboxOnly.firstUnsupported(in: [convert("srt", .subtitle)]) == nil
    )
  }

  @Test
  func `probed capabilities track encoder names and codec families`() {
    let capabilities = FFmpegCapabilities(
      version: nil,
      containers: [],
      videoCodecs: [
        FFmpegCodec(
          name: "libx265",
          summary: "libx265 H.265 / HEVC (codec hevc)",
          mediaType: .video,
          canEncode: true,
          canDecode: true
        ),
        FFmpegCodec(
          name: "libx264",
          summary: "libx264 H.264 (codec h264)",
          mediaType: .video,
          canEncode: false,
          canDecode: true
        )
      ],
      audioCodecs: [
        FFmpegCodec(
          name: "aac",
          summary: "AAC (Advanced Audio Coding)",
          mediaType: .audio,
          canEncode: true,
          canDecode: true
        )
      ],
      subtitleCodecs: []
    )

    let probed = EncoderCapabilities(probed: capabilities)

    // The encodable encoder name and its (codec …) family alias both resolve.
    #expect(probed.supportsVideo("libx265"))
    #expect(probed.supportsVideo("hevc"))
    #expect(probed.supportsAudio("aac"))
    // A decode-only encoder is not available for transcoding.
    #expect(!probed.supportsVideo("libx264"))
    #expect(!probed.supportsVideo("h264"))
  }
}
