import SwiftUI

/**
 The inset rhythm the window's chrome bars share, so ``DestinationBar`` and
 ``QueueStatusBar`` frame the queue with matching margins.
 */
private enum WindowBarInsets {
  static let horizontal: Double = 12
  static let vertical: Double = 6
}

extension View {
  /// Insets a window chrome bar's content to the rhythm its opposite bar uses.
  func windowBarInsets() -> some View {
    padding(.horizontal, WindowBarInsets.horizontal)
      .padding(.vertical, WindowBarInsets.vertical)
  }
}
