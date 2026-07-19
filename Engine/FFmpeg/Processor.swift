import Foundation

/**
 Processors are used to convert or transcode a video file according to a list
 of ``operations``.
 */
protocol Processor {

  /// The operations that will be performed.
  var operations: [StreamOperation] { get }
}

extension Processor {

  /**
   Returns `true` if a container does not need any processing (all
   operations are ``StreamOperation/Kind-swift.enum/copy``).
   */
  public func isNoop(container: Container) -> Bool {
    if operations.count != container.streams.count { return false }
    return operations.allSatisfy { $0.kind == .copy }
  }
}

/// Dry-runs a video file, describing what would be processed without processing it.
final class DryRunProcessor: Processor {
  private let inputURL: URL
  let operations: [StreamOperation]

  init(inputURL: URL, operations: [StreamOperation]) {
    self.inputURL = inputURL
    self.operations = operations
  }

  func process(outputURL: URL) throws {
    print("\(inputURL.path(percentEncoded: false)) -> \(outputURL.path(percentEncoded: false)):")
    for operation in operations { print("  \(description(operation: operation))") }
  }

  private func description(operation: StreamOperation) -> String {
    switch operation.kind {
      case .copy:
        "0:\(operation.streamIndex) (\(operation.streamType)): copy"
      case .convert(let codec, _):
        "0:\(operation.streamIndex) (\(operation.streamType)): transcode to \(codec)"
    }
  }
}
