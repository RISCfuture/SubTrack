import Foundation
import Testing

@testable import SubTrack_Common

@Suite
struct FFmpegDiscoveryTests {

  private func installation(
    _ path: String,
    version: String?,
    encoders: [String] = ["libx264"]
  ) -> FFmpegInstallation {
    FFmpegInstallation(
      directory: URL(filePath: path, directoryHint: .isDirectory),
      capabilities: FFmpegCapabilities(
        version: version.map {
          FFmpegVersionInfo(
            version: $0,
            bannerLine: "ffmpeg version \($0) Copyright (c) 2000-2026 the FFmpeg developers",
            configuration: nil,
            libraryVersions: []
          )
        },
        containers: [],
        videoCodecs: encoders.map {
          FFmpegCodec(
            name: $0,
            summary: $0,
            mediaType: .video,
            canEncode: true,
            canDecode: true
          )
        },
        audioCodecs: [],
        subtitleCodecs: []
      )
    )
  }

  @Test
  func `versions order across Homebrew, MacPorts, and snapshot spellings`() {
    let found = [
      installation("/usr/bin", version: "6.1.1-tessus"),
      installation("/opt/local/bin", version: "N-113579-g4a134eb14f"),
      installation("/opt/homebrew/bin", version: "8.1.2"),
      installation("/usr/local/bin", version: "n7.1")
    ]

    #expect(
      found.sorted(by: FFmpegDiscovery.isBetter).map(\.capabilities.version?.version) == [
        "8.1.2", "n7.1", "6.1.1-tessus", "N-113579-g4a134eb14f"
      ],
      "A git snapshot names no release, so it ranks behind every numbered build."
    )
  }

  @Test
  func `richer codec set breaks a version tie`() {
    let lean = installation("/usr/bin", version: "8.1.2", encoders: ["h264_videotoolbox"]),
      full = installation(
        "/opt/homebrew/bin",
        version: "8.1.2",
        encoders: ["libx264", "libx265", "libsvtav1"]
      )

    #expect(FFmpegDiscovery.isBetter(full, than: lean))
    #expect(!FFmpegDiscovery.isBetter(lean, than: full))
  }
}
