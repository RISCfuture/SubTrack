import SwiftUI

/**
 A searchable list of every catalog language; tapping toggles membership in the
 bound selection. The `StringListEditor` reconciles the resulting changes.
 */
struct LanguageBrowser: View {
  private static let browserSize = CGSize(width: 280, height: 340)

  @Binding var selected: [String]
  @State private var query = ""

  var body: some View {
    VStack(spacing: 0) {
      TextField("Search languages", text: $query)
        .textFieldStyle(.roundedBorder)
        .padding(8)
        .accessibilityIdentifier("language.search")
      List(matches) { language in
        Toggle(isOn: membership(of: language.code)) {
          HStack(spacing: 8) {
            Text(language.name)
            Spacer(minLength: 8)
            Text(language.code).font(.caption.monospaced()).foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.checkbox)
        .accessibilityIdentifier("language.row.\(language.code)")
      }
    }
    .frame(width: Self.browserSize.width, height: Self.browserSize.height)
  }

  private var matches: [LanguageCatalog.Language] {
    let query = query.trimmingCharacters(in: .whitespaces).lowercased()
    guard !query.isEmpty else { return LanguageCatalog.all }
    return LanguageCatalog.all.filter {
      $0.name.lowercased().contains(query) || $0.code.contains(query)
    }
  }

  /**
   Whether `code` is among the selected languages, as the binding each row's
   checkbox drives.
   */
  private func membership(of code: String) -> Binding<Bool> {
    Binding(
      get: { selected.contains(code) },
      set: { isSelected in
        if isSelected {
          guard !selected.contains(code) else { return }
          selected.append(code)
        } else {
          selected.removeAll { $0 == code }
        }
      }
    )
  }
}

#if DEBUG
  #Preview("Language Browser") {
    @Previewable @State var selected = ["eng", "jpn"]
    LanguageBrowser(selected: $selected)
  }
#endif
