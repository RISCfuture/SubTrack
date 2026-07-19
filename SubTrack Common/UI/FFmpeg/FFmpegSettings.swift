import Foundation
import os

/// Where the app finds `ffmpeg`/`ffprobe`.
public enum FFmpegLocationMode: String, Sendable, CaseIterable {
  /// The `ffmpeg` bundled in the app (falls back to the system `ffmpeg` in dev).
  case builtIn
  /// A user-chosen folder containing `ffmpeg` and `ffprobe`.
  case custom
}

/**
 Reads the user's FFmpeg-location preference and builds the matching locator.
 The read side is `UserDefaults`-based so the engine can resolve it off the
 main actor.
 */
enum FFmpegProvisioning {
  static let modeKey = "ffmpegLocationMode"
  static let directoryKey = "ffmpegCustomDirectory"

  private static let log = Logger(subsystem: "SubTrack", category: "FFmpegProvisioning")

  /// The locator for the current settings.
  static func makeLocator(fullCodecSet: Bool, defaults: UserDefaults = .standard)
    -> any FFmpegLocator
  {
    let capabilities: EncoderCapabilities = fullCodecSet ? .full : .videoToolboxOnly
    if defaults.string(forKey: modeKey) == FFmpegLocationMode.custom.rawValue,
      let directory = defaults.string(forKey: directoryKey), !directory.isEmpty
    {
      let base = URL(filePath: directory, directoryHint: .isDirectory)
      return ExplicitFFmpegLocator(
        ffmpeg: base.appending(path: "ffmpeg", directoryHint: .notDirectory),
        ffprobe: base.appending(path: "ffprobe", directoryHint: .notDirectory),
        capabilities: capabilities
      )
    }
    return builtInLocator(capabilities: capabilities)
  }

  /// The bundled binary when present, otherwise the system `ffmpeg` (dev).
  static func builtInLocator(capabilities: EncoderCapabilities) -> any FFmpegLocator {
    let bundled = BundledFFmpegLocator(capabilities: capabilities)
    if FileManager.default.isExecutableFile(atPath: bundled.ffmpegURL.path(percentEncoded: false)) {
      return bundled
    }
    if let system = try? SystemFFmpegLocator(capabilities: capabilities) { return system }
    let reason = FFmpegToolError.executableNotFound(name: "ffmpeg").userMessage
    log.error(
      "No runnable ffmpeg found; using non-runnable bundled locator: \(reason, privacy: .public)"
    )
    return bundled
  }
}

/// The main-actor, observable binding surface for the FFmpeg-location setting.
@MainActor
@Observable
public final class FFmpegSettingsStore {
  /// Where `ffmpeg`/`ffprobe` are resolved from, persisted to `UserDefaults` on change.
  public var mode: FFmpegLocationMode {
    didSet {
      UserDefaults.standard.set(mode.rawValue, forKey: FFmpegProvisioning.modeKey)
      onChange?()
    }
  }

  /**
   The user-chosen folder holding `ffmpeg` and `ffprobe`, consulted only while
   ``mode`` is ``FFmpegLocationMode/custom``. Persisted to `UserDefaults` on
   change.
   */
  public var customDirectory: String {
    didSet {
      UserDefaults.standard.set(customDirectory, forKey: FFmpegProvisioning.directoryKey)
      onChange?()
    }
  }

  /**
   Invoked after the resolved FFmpeg location changes, so dependents (the
   queue) can refresh capabilities and revalidate items.
   */
  public var onChange: (@MainActor () -> Void)?

  /// Whether the custom folder actually contains runnable `ffmpeg` + `ffprobe`.
  public var customIsValid: Bool {
    guard !customDirectory.isEmpty else { return false }
    let base = URL(filePath: customDirectory, directoryHint: .isDirectory)
    let fileManager = FileManager.default
    return fileManager.isExecutableFile(
      atPath: base.appending(path: "ffmpeg").path(percentEncoded: false)
    )
      && fileManager.isExecutableFile(
        atPath: base.appending(path: "ffprobe").path(percentEncoded: false)
      )
  }

  /// Creates a store seeded with the location mode and folder last chosen in Settings.
  public init() {
    let defaults = UserDefaults.standard
    mode =
      FFmpegLocationMode(rawValue: defaults.string(forKey: FFmpegProvisioning.modeKey) ?? "")
      ?? .builtIn
    customDirectory = defaults.string(forKey: FFmpegProvisioning.directoryKey) ?? ""
  }
}
