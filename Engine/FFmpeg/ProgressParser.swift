import Foundation

/**
 Incrementally parses `ffmpeg -progress` output into ``ConversionProgress``
 values. Pure and side-effect free, so it can be unit-tested without running
 `ffmpeg`.

 `ffmpeg` emits `key=value` lines grouped into blocks; each block ends with a
 `progress=continue` (or `progress=end`) line. Feed lines one at a time; a
 value is returned whenever a block completes.
 */
struct ProgressParser {

  /// The total source duration, used to compute ``ConversionProgress/fraction``.
  let totalDuration: Duration

  private var pending: [String: String] = [:]

  /// Creates a parser that reports progress as a fraction of `totalDuration`.
  init(totalDuration: Duration) {
    self.totalDuration = totalDuration
  }

  /// Parses an `HH:MM:SS.ffffff` timestamp into seconds.
  static func seconds(fromTimestamp timestamp: String) -> Double? {
    let parts = timestamp.split(separator: ":")
    guard parts.count == 3, let hours = Double(parts[0]), let minutes = Double(parts[1]),
      let seconds = Double(parts[2])
    else {
      return nil
    }
    return hours * 3600 + minutes * 60 + seconds
  }

  /**
   Feeds one line of `ffmpeg -progress` output.

   - Returns: A ``ConversionProgress`` when the line completes a block,
     otherwise `nil`.
   */
  mutating func consume(line: String) -> ConversionProgress? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard let separator = trimmed.firstIndex(of: "=") else { return nil }
    let key = String(trimmed[trimmed.startIndex..<separator])
    let value = String(trimmed[trimmed.index(after: separator)...])

    guard key == "progress" else {
      pending[key] = value
      return nil
    }

    defer { pending.removeAll(keepingCapacity: true) }
    return progress(ending: value == "end")
  }

  private func progress(ending: Bool) -> ConversionProgress {
    let outTime = parsedOutTime()
    let fraction = ending ? 1 : self.fraction(for: outTime)
    return ConversionProgress(
      fraction: fraction,
      outTime: outTime,
      speed: parsedSpeed(),
      totalSize: pending["total_size"].flatMap(Int.init)
    )
  }

  private func fraction(for outTime: Duration) -> Double? {
    let total = totalDuration.seconds
    guard total > 0 else { return nil }
    return min(max(outTime.seconds / total, 0), 1)
  }

  /**
   `ffmpeg` reports `out_time_us` in microseconds. Historically `out_time_ms`
   was mislabelled and also carried microseconds, so it is used as a fallback
   with the same scale before falling back to the `HH:MM:SS.ffffff` string.
   */
  private func parsedOutTime() -> Duration {
    if let microseconds = pending["out_time_us"].flatMap(Int64.init) {
      return .microseconds(microseconds)
    }
    if let microseconds = pending["out_time_ms"].flatMap(Int64.init) {
      return .microseconds(microseconds)
    }
    if let formatted = pending["out_time"], let seconds = Self.seconds(fromTimestamp: formatted) {
      return .seconds(seconds)
    }
    return .zero
  }

  private func parsedSpeed() -> Double? {
    guard let raw = pending["speed"] else { return nil }
    let trimmed = raw.hasSuffix("x") ? String(raw.dropLast()) : raw
    return Double(trimmed.trimmingCharacters(in: .whitespaces))
  }
}

extension Duration {
  /// The duration expressed as a floating-point number of seconds.
  var seconds: Double {
    let components = self.components
    return Double(components.seconds) + Double(components.attoseconds) / 1e18
  }
}
