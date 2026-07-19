import Foundation

/**
 Describes which encoders a particular `ffmpeg` build can use, so the engine
 can reject an unsupported transcode before invoking `ffmpeg` (rather than
 surfacing an opaque non-zero exit).
 */
public struct EncoderCapabilities: Sendable, Equatable {

  /// A full `ffmpeg` build (Developer-ID download build): all encoders allowed.
  public static let full = Self(allowsAll: true)

  /**
   A reduced LGPL build (Mac App Store build): hardware VideoToolbox video
   encoders plus royalty-free/native audio encoders only.
   */
  public static let videoToolboxOnly = Self(
    allowsAll: false,
    videoEncoders: ["hevc_videotoolbox", "h264_videotoolbox"],
    audioEncoders: ["aac", "ac3", "eac3", "flac", "alac", "opus", "libopus"]
  )

  /// When `true`, every encoder is assumed available (a full `ffmpeg` build).
  public var allowsAll: Bool

  /// Video encoder names available when ``allowsAll`` is `false`.
  public var videoEncoders: Set<String>

  /// Audio encoder names available when ``allowsAll`` is `false`.
  public var audioEncoders: Set<String>

  public init(allowsAll: Bool, videoEncoders: Set<String> = [], audioEncoders: Set<String> = []) {
    self.allowsAll = allowsAll
    self.videoEncoders = videoEncoders
    self.audioEncoders = audioEncoders
  }

  /**
   Derives capabilities from a live probe of a resolved `ffmpeg` binary, so
   compatibility reflects the encoders that build actually ships rather than
   the coarse build-type bucket. Each encodable codec contributes both its
   encoder name (e.g. `libx265`) and, when `ffmpeg` annotates the row with a
   `(codec …)` family, the family name (e.g. `hevc`) — so both encoder-name
   and codec-name transcode targets resolve correctly.
   */
  public init(probed capabilities: FFmpegCapabilities) {
    self.allowsAll = false
    self.videoEncoders = Self.encoderNames(in: capabilities.videoCodecs)
    self.audioEncoders = Self.encoderNames(in: capabilities.audioCodecs)
  }

  /// The encodable codecs' encoder names plus any `(codec …)` family aliases.
  private static func encoderNames(in codecs: [FFmpegCodec]) -> Set<String> {
    var names = Set<String>()
    for codec in codecs where codec.canEncode {
      names.insert(codec.name)
      if let family = codec.family { names.insert(family) }
    }
    return names
  }

  /**
   Whether this build can write the named video codec. `copy` always passes,
   as it encodes nothing, and ``allowsAll`` bypasses the encoder-set check.
   */
  public func supportsVideo(_ codec: String) -> Bool {
    codec == "copy" || allowsAll || videoEncoders.contains(codec)
  }

  /**
   Whether this build can write the named audio codec. `copy` always passes,
   as it encodes nothing, and ``allowsAll`` bypasses the encoder-set check.
   */
  public func supportsAudio(_ codec: String) -> Bool {
    codec == "copy" || allowsAll || audioEncoders.contains(codec)
  }

  /**
   The first transcode operation whose target encoder this build cannot
   provide, as a `(streamType, codec)` pair, or `nil` when every operation is
   supported. Copies and subtitle transcodes never fail this check. This is
   the single shared compatibility checkpoint used by both the engine's
   pre-run guard and the queue's item-state validation.
   */
  public func firstUnsupported(
    in operations: [StreamOperation]
  ) -> (StreamOperation.StreamType, String)? {
    for operation in operations {
      guard case let .convert(codec, _) = operation.kind else { continue }
      let supported: Bool
      switch operation.streamType {
        case .video: supported = supportsVideo(codec)
        case .audio: supported = supportsAudio(codec)
        case .subtitle: supported = true
      }
      if !supported { return (operation.streamType, codec) }
    }
    return nil
  }
}

/**
 Resolves the `ffmpeg`/`ffprobe` executables and the encoder capabilities of
 that build. Injected per executable target so the shared engine stays
 build-agnostic.
 */
protocol FFmpegLocator: Sendable {
  /// The `ffmpeg` executable used to transcode.
  var ffmpegURL: URL { get }
  /// The `ffprobe` executable used to inspect media and verify output.
  var ffprobeURL: URL { get }
  /// The encoders the resolved build can write with.
  var capabilities: EncoderCapabilities { get }
}

/// A locator with explicitly provided executable URLs (CLI flags, tests).
struct ExplicitFFmpegLocator: FFmpegLocator {
  let ffmpegURL: URL
  let ffprobeURL: URL
  let capabilities: EncoderCapabilities

  init(ffmpeg: URL, ffprobe: URL, capabilities: EncoderCapabilities = .full) {
    self.ffmpegURL = ffmpeg
    self.ffprobeURL = ffprobe
    self.capabilities = capabilities
  }
}

/// Locates `ffmpeg`/`ffprobe` on the user's `$PATH` (used by the CLI).
struct SystemFFmpegLocator: FFmpegLocator {
  let ffmpegURL: URL
  let ffprobeURL: URL
  let capabilities: EncoderCapabilities

  init(capabilities: EncoderCapabilities = .full) throws {
    guard let ffmpeg = try which("ffmpeg") else {
      throw FFmpegToolError.executableNotFound(name: "ffmpeg")
    }
    guard let ffprobe = try which("ffprobe") else {
      throw FFmpegToolError.executableNotFound(name: "ffprobe")
    }
    self.ffmpegURL = ffmpeg
    self.ffprobeURL = ffprobe
    self.capabilities = capabilities
  }
}

/**
 Locates `ffmpeg`/`ffprobe` bundled inside an app at `Contents/Helpers`
 (used by both app targets).
 */
struct BundledFFmpegLocator: FFmpegLocator {
  let ffmpegURL: URL
  let ffprobeURL: URL
  let capabilities: EncoderCapabilities

  init(bundle: Bundle = .main, capabilities: EncoderCapabilities) {
    let helpers = bundle.bundleURL.appending(path: "Contents/Helpers", directoryHint: .isDirectory)
    self.ffmpegURL = helpers.appending(path: "ffmpeg", directoryHint: .notDirectory)
    self.ffprobeURL = helpers.appending(path: "ffprobe", directoryHint: .notDirectory)
    self.capabilities = capabilities
  }
}
