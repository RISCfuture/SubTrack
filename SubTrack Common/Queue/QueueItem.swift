public import Foundation

/// The lifecycle state of a queued file.
public enum QueueItemState: Sendable, Equatable {
  /// Queued, not yet inspected.
  case waiting
  /// `ffprobe` is reading the source.
  case probing
  /// Inspected and ready to run.
  case ready
  /// Encoding is in progress (see ``QueueItem/progress``).
  case running
  /// Finished successfully.
  case done
  /// Cancelled by the user.
  case cancelled
  /// The source file is missing or unreadable.
  case missing
  /**
   The selected `ffmpeg` build can't perform this item's transcode; carries a
   user-facing reason. Recovers when a capable binary or codec is chosen.
   */
  case incompatible(String)
  /// Failed with a human-readable message.
  case failed(String)
}

extension QueueItemState {
  /// Whether the item can be (re)started.
  public var isStartable: Bool {
    switch self {
      case .waiting, .ready, .cancelled, .failed: true
      case .probing, .running, .done, .missing, .incompatible: false
    }
  }

  /// Whether the item is doing work right now, so cancelling it means something.
  public var isActive: Bool { self == .probing || self == .running }

  /**
   Whether the item is in a state that warrants a sidebar warning: a missing
   source, a failed run, or an encode the selected build can't perform.
   */
  public var needsAttention: Bool {
    switch self {
      case .missing, .failed, .incompatible: true
      case .waiting, .probing, .ready, .running, .done, .cancelled: false
    }
  }

  /**
   Whether the item may be dragged to change the run order. Excludes items
   that are running, finished, being probed, or missing — reordering those
   can't affect (or would disrupt) the pending run order. An incompatible
   item is still pending, so it stays reorderable like a failed one.
   */
  public var isReorderable: Bool {
    switch self {
      case .waiting, .ready, .cancelled, .failed, .incompatible: true
      case .probing, .running, .done, .missing: false
    }
  }

  /**
   Whether the item can be re-probed. A probe only reads the source, so every
   settled state qualifies; only an in-flight probe or encode does not.
   */
  public var isRescannable: Bool { !isActive }

  /**
   Whether the item's output path names a file on disk. A run stages its
   output elsewhere and moves it into place only once it has verified, so a
   running item has nothing at that path yet.
   */
  public var holdsWrittenOutput: Bool { self == .done }

  /**
   Whether a change to the queue's name format must leave the item's output
   path alone: a finished run's file is on disk under that name, and a running
   one is already committed to writing it there.
   */
  public var keepsOutputPath: Bool { self == .done || self == .running }
}

/**
 A single file in the conversion queue. Observable so the UI reacts to
 status/progress changes.
 */
@MainActor
@Observable
public final class QueueItem: Identifiable {
  /**
   The completed fraction below which ``projectedOutputByteCount`` withholds a
   projection: container headers and the first keyframes make the opening
   moments of an encode wildly unrepresentative of its eventual rate.
   */
  private static let minimumProjectableProgress = 0.05

  public let id = UUID()

  /// The source video file.
  public let sourceURL: URL

  /// The destination file (may be overridden per item).
  public var outputURL: URL

  /**
   The base name the user gave this one file, overriding the queue's name
   format; `nil` when the format names it. The source's extension is appended
   either way. Set through ``QueueCoordinator/setCustomName(_:for:)``, which
   restates the output path and persists the edit.
   */
  public var customName: String?

  /**
   A security-scoped bookmark to ``sourceURL``, letting the file be reached
   after relaunch (and its scope re-entered for each encode); `nil` when one
   couldn't be created, such as for a synthetic URL.
   */
  public var sourceBookmark: Data?

  /**
   A security-scoped bookmark to the folder ``outputURL`` is written into,
   needed because ``sourceBookmark`` scopes the source *file* and a
   file-scoped grant can't create a sibling beside it. Only meaningful for
   output written outside the queue's destination folder — the destination
   carries its own bookmark. `nil` when the folder wasn't reachable at add
   time, which leaves the run to fail with ``FileAccessError/accessDenied(url:)``.
   */
  public var outputFolderBookmark: Data?

  /**
   The item's current lifecycle state, driven by the coordinator as it probes,
   runs, and settles the item.
   */
  public var status: QueueItemState = .waiting

  /// Completion fraction in `0...1` while ``status`` is ``QueueItemState/running``.
  public var progress: Double = 0

  /// The probed container, once inspected.
  public var container: Container?

  /// A per-file track override; when `nil`, the global rules apply.
  public var selection: FileTrackSelection?

  /// The source file size in bytes, if known.
  public var sourceByteCount: Int?

  /**
   The output file size in bytes, captured when the item finishes; `nil` until
   then (or when the output couldn't be stat'd).
   */
  public var outputByteCount: Int?

  /**
   How many bytes `ffmpeg` reports having written so far in the current run;
   `nil` outside of one, and while a run has yet to report.
   */
  public var writtenByteCount: Int?

  /**
   How many managed (video/audio/subtitle) tracks the completed run dropped —
   the probed track count minus the kept-operation count; `nil` until finished.
   */
  public var tracksRemoved: Int?

  /// The most recent failure message, if any.
  public var lastError: String?

  /// The file name shown in the queue.
  public var displayName: String { sourceURL.lastPathComponent }

  /// A short "1V 2A 1S" style summary of the probed tracks.
  public var trackSummary: String? {
    guard let container else { return nil }
    var parts = [String]()
    if !container.videoStreams.isEmpty {
      parts.append(
        String(localized: "\(container.videoStreams.count, format: .number)V", bundle: #bundle)
      )
    }
    if !container.audioStreams.isEmpty {
      parts.append(
        String(localized: "\(container.audioStreams.count, format: .number)A", bundle: #bundle)
      )
    }
    if !container.subtitleStreams.isEmpty {
      parts.append(
        String(localized: "\(container.subtitleStreams.count, format: .number)S", bundle: #bundle)
      )
    }
    return parts.isEmpty ? nil : parts.joined(separator: " ")
  }

  /**
   The number of managed (video/audio/subtitle) tracks in the probed source,
   or `nil` before the container is known.
   */
  public var managedTrackCount: Int? {
    container?.managedStreams.count
  }

  /**
   How many managed tracks the last finished output holds — the probed count
   less the tracks that run dropped. `nil` until a run records a result, and
   stale once a re-scan or re-run supersedes it.
   */
  public var finishedTrackCount: Int? {
    guard let managedTrackCount, let tracksRemoved else { return nil }
    return managedTrackCount - tracksRemoved
  }

  /**
   How much of this item's work is behind it (`0...1`): all of it once done,
   the live fraction while encoding, and none of it in every other state.
   */
  var progressWeight: Double {
    switch status {
      case .done: 1
      case .running: progress
      default: 0
    }
  }

  /**
   The output size the in-flight run is on course for, extrapolated from the
   bytes written so far against the fraction they cover. `nil` outside a run,
   or before enough of one has elapsed for the extrapolation to settle.
   */
  public var projectedOutputByteCount: Int? {
    guard status == .running, progress >= Self.minimumProjectableProgress, let writtenByteCount
    else {
      return nil
    }
    return Int(Double(writtenByteCount) / progress)
  }

  public init(sourceURL: URL, outputURL: URL) {
    self.sourceURL = sourceURL
    self.outputURL = outputURL
  }

  /**
   Builds the engine job for this item, reading from `source` (the
   bookmark-resolved location when one is available, otherwise ``sourceURL``)
   and using the given global rules — the latter only when the item has no
   per-file `selection`.
   */
  func makeJob(source: URL, globalRules: SlimRules, verify: Bool = true) -> SlimJob {
    SlimJob(
      input: source,
      output: outputURL,
      selection: selection,
      rules: selection == nil ? globalRules : nil,
      verify: verify
    )
  }
}
