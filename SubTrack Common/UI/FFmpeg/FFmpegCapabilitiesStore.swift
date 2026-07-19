import Foundation

/**
 Main-actor state holder that probes the currently-resolved `ffmpeg` build
 and publishes its version and supported formats to the Settings UI.
 Re-probing is driven by the view whenever the FFmpeg-location setting
 changes.
 */
@MainActor
@Observable
public final class FFmpegCapabilitiesStore {

  /// The most recent probe's state, published to the Settings UI.
  public private(set) var state: State = .idle

  /// Creates a store already holding `state`, so callers can seed a fixture.
  public init(state: State = .idle) {
    self.state = state
  }

  /**
   Probes the build resolved from the current location setting. Runs the
   binary off the main actor; safe to call from a cancellable `.task`.
   */
  public func load(fullCodecSet: Bool) async {
    state = .loading
    let ffmpegURL = FFmpegProvisioning.makeLocator(fullCodecSet: fullCodecSet).ffmpegURL
    let outcome = await FFmpegProbe(ffmpegURL: ffmpegURL).run()
    guard !Task.isCancelled else { return }
    switch outcome {
      case .success(let capabilities): state = .loaded(capabilities)
      case .unavailable(let reason): state = .unavailable(reason)
    }
  }

  /// The lifecycle of a single probe.
  public enum State: Sendable, Equatable {
    case idle
    case loading
    case loaded(FFmpegCapabilities)
    case unavailable(String)
  }
}

#if DEBUG
  extension FFmpegCapabilitiesStore {
    /// Seeds a fixed state for previews, which don't have a runnable `ffmpeg`.
    func setForPreview(_ state: State) { self.state = state }
  }
#endif
