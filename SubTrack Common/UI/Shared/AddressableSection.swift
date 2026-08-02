import SwiftUI

extension View {
  /**
   Names this editor as one element, so a Help-book capture can frame the part
   of a form an article is about rather than the whole pane.

   The inspector's sections all fit inside a single pane-height screenshot, so
   articles about different parts of it would otherwise each ship the same
   picture. It has to go on the editor rather than the enclosing `Section`,
   which cannot be framed: SwiftUI stamps a section's identifier onto each row
   it emits instead of emitting one element spanning them, so a query for it
   answers with a heading or a single row. `.contain` keeps every control
   inside a queryable descendant rather than collapsing them into one element,
   which is what lets the tests that drive those controls go on finding them.
   */
  func addressableSection(_ identifier: String) -> some View {
    accessibilityElement(children: .contain)
      .accessibilityIdentifier(identifier)
  }
}
