import SwiftUI

/**
 The languages-to-keep row: a summary of the chosen languages and an **Edit…**
 button presenting a ``StringListEditor``. The editor's `+` menu opens a
 searchable ``LanguageBrowser`` (there are hundreds of codes) and an `Other`
 item for a raw code.
 */
struct LanguagePickerButton: View {
  @Binding var languages: [String]
  @State private var showingEditor = false
  @State private var showingBrowser = false

  var body: some View {
    LabeledContent("Languages") {
      EditableSummary(summary: summary, accessibilityIdentifier: "rules.languages") {
        showingEditor = true
      }
      .popover(isPresented: $showingEditor) {
        StringListEditor(
          values: $languages,
          accessibilityIdentifier: "rules.languages",
          reorderable: true,
          placeholder: "code",
          resolvedLabel: { LanguageCatalog.name(for: $0) },
          isKnown: { LanguageCatalog.name(for: $0) != nil },
          warningHelp: "Not a recognized ISO 639-2 language code.",
          extraActions: [
            CodeAction(title: "Browse Languages…") {
              showingEditor = false
              showingBrowser = true
            }
          ]
        )
      }
      .popover(isPresented: $showingBrowser) { LanguageBrowser(selected: $languages) }
    }
  }

  private var summary: String {
    languages.isEmpty
      ? String(localized: "None", bundle: #bundle)
      : languages.map { LanguageCatalog.name(for: $0) ?? $0 }.joined(separator: ", ")
  }
}

#if DEBUG
  #Preview("Language Row") {
    @Previewable @State var languages = ["eng", "jpn", "zzz"]
    Form {
      LanguagePickerButton(languages: $languages)
    }
    .formStyle(.grouped)
    .frame(width: 320)
  }
#endif
