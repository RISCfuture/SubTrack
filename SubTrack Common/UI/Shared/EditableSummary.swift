import SwiftUI

/**
 A read-only summary of a list value plus an **Edit…** button that makes it
 obvious the row opens an editor. Shared by the language and preferred-codec
 rows so they present identically.
 */
struct EditableSummary: View {
  let summary: String

  /**
   Names the list this row edits, so a test can tell the languages row from
   each of the preferred-codec rows. The summary takes it as-is and the button
   takes its `.edit` form.
   */
  let accessibilityIdentifier: String
  let edit: () -> Void

  var body: some View {
    HStack {
      Text(summary)
        .lineLimit(1)
        .truncationMode(.middle)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier(accessibilityIdentifier)
      Button("Edit", action: edit)
        .accessibilityIdentifier("\(accessibilityIdentifier).edit")
    }
  }
}

#if DEBUG
  #Preview("Editable Summary") {
    Form {
      LabeledContent("Empty") {
        EditableSummary(summary: "", accessibilityIdentifier: "preview.empty") {}
      }
      LabeledContent("Truncated") {
        EditableSummary(
          summary: "English, Japanese, French, German, Spanish, Italian, Portuguese, Korean",
          accessibilityIdentifier: "preview.truncated"
        ) {}
      }
    }
    .formStyle(.grouped)
    .frame(width: 320)
  }
#endif
