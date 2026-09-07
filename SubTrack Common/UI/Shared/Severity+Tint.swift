import SwiftUI

extension Severity {
  /**
   The colour this tier reads in: red for a problem, orange for a warning, and
   the secondary shade for a note.

   The single place a tier becomes a colour. ``Severity`` itself stays free of
   SwiftUI so the model layer — and the command-line tool, which has no AppKit
   — can name a tier without drawing one.
   */
  var tint: Color {
    switch self {
      case .note: .secondary
      case .warning: .orange
      case .problem: .red
    }
  }
}
