import SwiftUI

/// A known value the `+` menu can append directly.
struct CodeChoice: Identifiable {
  let id = UUID()
  let title: String
  let code: String
}

/**
 An extra `+` menu item that runs an action rather than appending a value
 (e.g. "Browse Languages…").
 */
struct CodeAction: Identifiable {
  let id = UUID()
  let title: LocalizedStringKey
  let action: () -> Void
}

/**
 An Xcode-Build-Settings-style list editor: each value is an inline-editable
 row showing the raw code, with a dimmed resolved label and a warning triangle
 for unrecognized values, plus `+`/`−` controls and optional drag-reordering.

 Presented inside a popover. Edits a local, stably-identified copy of the rows
 so reordering and half-typed entries stay put, and writes trimmed,
 de-duplicated, non-empty values back through its `values` binding. Every row
 emits the same view tree whatever its content, toggling the optional label and
 warning with opacity.
 */
struct StringListEditor: View {
  /// Which rows a drag moves, and where to.
  private typealias Reorder = ReorderDifference<Row.ID, ReorderableSingleCollectionIdentifier>

  private static let rowListHeight = 196.0
  private static let popoverWidth = 320.0

  @Binding var values: [String]

  /**
   Names the list being edited, so a test can address this editor's controls:
   `<id>.add` is the `+` menu, and each row carries `<id>.row.<code>` and
   `<id>.remove.<code>` for the code it currently holds.
   */
  let accessibilityIdentifier: String
  let reorderable: Bool
  let placeholder: LocalizedStringKey
  /**
   The dimmed secondary label for a code (e.g. a language or codec name), or
   `nil` to show none.
   */
  let resolvedLabel: (String) -> String?
  /// Whether a code is recognized/supported; `false` shows the warning triangle.
  let isKnown: (String) -> Bool
  /// The tooltip shown on the warning triangle for an unrecognized code.
  let warningHelp: LocalizedStringKey
  /// Known values listed in the `+` menu; each appends its code.
  let knownValues: [CodeChoice]
  /// Extra `+` menu items (e.g. a browser); each runs its own action.
  let extraActions: [CodeAction]

  @State private var rows: [Row]
  @FocusState private var focused: UUID?

  // The rows are a plain `ScrollView` stack rather than a `List`:
  // `reorderable()` needs no `List`, and a `List`'s reorder drag recognizer
  // delays focus reaching an inline `TextField`. Each row and the divider
  // below it form one view, so one reorderable item is one row.
  var body: some View {
    VStack(spacing: 0) {
      ScrollView {
        VStack(spacing: 0) {
          ForEach(rows) { row in
            VStack(spacing: 0) {
              CodeRow(
                text: binding(for: row.id),
                focused: $focused,
                id: row.id,
                accessibilityIdentifier: accessibilityIdentifier,
                reorderable: reorderable,
                placeholder: placeholder,
                resolvedLabel: resolvedLabel,
                isKnown: isKnown,
                warningHelp: warningHelp,
                onRemove: { removeRow(row.id) }
              )
              if row.id != rows.last?.id { Divider() }
            }
          }
          .reorderable()
        }
        .padding(.vertical, 4)
      }
      .frame(height: Self.rowListHeight)
      .reorderContainer(for: Row.self, isEnabled: reorderable, move: move)
      Divider()
      AddCodeBar(
        accessibilityIdentifier: "\(accessibilityIdentifier).add",
        knownValues: knownValues,
        extraActions: extraActions,
        onAppend: append,
        onAddBlank: addBlank
      )
    }
    .frame(width: Self.popoverWidth)
    .onChange(of: values, initial: false) { _, _ in reconcile() }
  }

  init(
    values: Binding<[String]>,
    accessibilityIdentifier: String,
    reorderable: Bool = false,
    placeholder: LocalizedStringKey = "code",
    resolvedLabel: @escaping (String) -> String?,
    isKnown: @escaping (String) -> Bool,
    warningHelp: LocalizedStringKey,
    knownValues: [CodeChoice] = [],
    extraActions: [CodeAction] = []
  ) {
    _values = values
    self.accessibilityIdentifier = accessibilityIdentifier
    self.reorderable = reorderable
    self.placeholder = placeholder
    self.resolvedLabel = resolvedLabel
    self.isKnown = isKnown
    self.warningHelp = warningHelp
    self.knownValues = knownValues
    self.extraActions = extraActions
    // Seed the stably-identified rows before first layout, so the row stack is
    // never mutated during its own update cycle.
    _rows = State(initialValue: values.wrappedValue.map { Row(text: $0) })
  }

  private func binding(for id: UUID) -> Binding<String> {
    Binding(
      get: { rows.first { $0.id == id }?.text ?? "" },
      set: { newValue in
        if let index = rows.firstIndex(where: { $0.id == id }) {
          rows[index].text = newValue
          writeBack()
        }
      }
    )
  }

  // MARK: - Mutations

  private func writeBack() {
    var seen = Set<String>()
    let next = rows.compactMap { row -> String? in
      let code = row.text.trimmingCharacters(in: .whitespaces)
      guard !code.isEmpty, seen.insert(code).inserted else { return nil }
      return code
    }
    if next != values { values = next }
  }

  /**
   Reflects values changed outside the editor (e.g. the language browser):
   adds rows for new codes and drops rows whose code is no longer present,
   while leaving blank in-progress rows alone. No-ops when the rows already
   match, so a write-back can't ricochet back into a row mutation.
   */
  private func reconcile() {
    let valueSet = Set(values)
    let present = Set(rows.map { $0.text.trimmingCharacters(in: .whitespaces) })
    let additions = values.filter { !present.contains($0) }
    let hasStale = rows.contains { row in
      let code = row.text.trimmingCharacters(in: .whitespaces)
      return !code.isEmpty && !valueSet.contains(code)
    }
    guard !additions.isEmpty || hasStale else { return }
    rows.removeAll { row in
      let code = row.text.trimmingCharacters(in: .whitespaces)
      return !code.isEmpty && !valueSet.contains(code)
    }
    rows.append(contentsOf: additions.map { Row(text: $0) })
  }

  private func append(_ code: String) {
    let trimmed = code.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty,
      !rows.contains(where: { $0.text.trimmingCharacters(in: .whitespaces) == trimmed })
    else { return }
    rows.append(Row(text: trimmed))
    writeBack()
  }

  private func addBlank() {
    let row = Row(text: "")
    rows.append(row)
    focused = row.id
  }

  private func removeRow(_ id: UUID) {
    rows.removeAll { $0.id == id }
    writeBack()
  }

  /// Applies a drag-reorder of the row stack.
  private func move(_ reorder: Reorder) {
    let dragged = Set(reorder.sources)
    let sources = IndexSet(rows.indices.filter { dragged.contains(rows[$0].id) })
    rows.move(fromOffsets: sources, toOffset: offset(of: reorder.destination.position))
    writeBack()
  }

  /// Where in `rows` the dragged rows land.
  private func offset(of position: Reorder.Destination.Position) -> Int {
    switch position {
      case .before(let targetID): rows.firstIndex { $0.id == targetID } ?? rows.endIndex
      case .end: rows.endIndex
    }
  }

  private struct Row: Identifiable, Equatable {
    let id = UUID()
    var text: String
  }
}

/**
 One inline-editable row of ``StringListEditor``: the raw code, its dimmed
 resolved label, a warning triangle for unrecognized codes, and a remove
 button.

 A reorderable row shows a grip handle marking it as draggable; the drag itself
 is driven by ``StringListEditor``'s reorder container.
 */
private struct CodeRow: View {
  private static let codeFieldWidth = 54.0

  @Binding var text: String
  @FocusState.Binding var focused: UUID?
  /// The row's identity, used for focus.
  let id: UUID

  /// The owning editor's identifier; this row's controls hang off the code it holds.
  let accessibilityIdentifier: String
  let reorderable: Bool
  let placeholder: LocalizedStringKey
  let resolvedLabel: (String) -> String?
  let isKnown: (String) -> Bool
  let warningHelp: LocalizedStringKey
  let onRemove: () -> Void

  private var code: String { text.trimmingCharacters(in: .whitespaces) }
  private var showsWarning: Bool { !code.isEmpty && !isKnown(code) }

  var body: some View {
    HStack(spacing: 8) {
      if reorderable {
        Image(systemName: "line.3.horizontal")
          .foregroundStyle(.secondary)
          .help("Drag to reorder")
          .accessibilityLabel(Text("Reorder", bundle: #bundle))
      }
      TextField(placeholder, text: $text)
        .textFieldStyle(.plain)
        .font(.body.monospaced())
        .multilineTextAlignment(.leading)
        .focused($focused, equals: id)
        .frame(width: Self.codeFieldWidth, alignment: .leading)
        .accessibilityIdentifier("\(accessibilityIdentifier).row.\(code)")
      Text(resolvedLabel(code) ?? "")
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.tail)
      Spacer(minLength: 0)
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)
        .help(warningHelp)
        .opacity(showsWarning ? 1 : 0)
        .accessibilityLabel(Text("Unrecognized code", bundle: #bundle))
        .accessibilityHidden(!showsWarning)
      Button(action: onRemove) {
        Label(LocalizedStringResource("Remove", bundle: #bundle), systemImage: "minus.circle.fill")
      }
      .buttonStyle(.borderless)
      .labelStyle(.iconOnly)
      .foregroundStyle(.secondary)
      .help("Remove")
      .accessibilityIdentifier("\(accessibilityIdentifier).remove.\(code)")
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 6)
    .contentShape(.rect)
  }
}

/**
 The `+` menu below ``StringListEditor``'s rows: known values append
 directly, extra actions run their own handler, and "Other" adds a blank row
 ready for typing.
 */
private struct AddCodeBar: View {
  let accessibilityIdentifier: String
  let knownValues: [CodeChoice]
  let extraActions: [CodeAction]
  let onAppend: (String) -> Void
  let onAddBlank: () -> Void

  var body: some View {
    HStack(spacing: 4) {
      Menu {
        ForEach(knownValues) { choice in
          Button(choice.title) { onAppend(choice.code) }
        }
        ForEach(extraActions) { action in
          Button(action.title, action: action.action)
        }
        if !knownValues.isEmpty || !extraActions.isEmpty { Divider() }
        Button(LocalizedStringResource("Other", bundle: #bundle), action: onAddBlank)
      } label: {
        Label(LocalizedStringResource("Add", bundle: #bundle), systemImage: "plus")
      }
      .menuStyle(.borderlessButton)
      .fixedSize()
      .accessibilityIdentifier(accessibilityIdentifier)
      Spacer()
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 5)
  }
}

#if DEBUG
  #Preview("String List Editor") {
    @Previewable @State var values = ["hevc", "h264", "vp9x"]
    let known = Set(["hevc", "h264", "av1", "vp9", "mpeg2video"])
    StringListEditor(
      values: $values,
      accessibilityIdentifier: "preview.codecs",
      reorderable: true,
      placeholder: "codec",
      resolvedLabel: { known.contains($0) ? $0.uppercased() : nil },
      isKnown: { known.contains($0) },
      warningHelp: "This codec isn’t in the current FFmpeg build.",
      knownValues: ["av1", "vp9", "mpeg2video"].map { CodeChoice(title: $0, code: $0) }
    )
  }

  #Preview("String List Editor — empty") {
    @Previewable @State var values: [String] = []
    StringListEditor(
      values: $values,
      accessibilityIdentifier: "preview.codecs",
      placeholder: "codec",
      resolvedLabel: { _ in nil },
      isKnown: { _ in true },
      warningHelp: "This codec isn’t in the current FFmpeg build."
    )
  }
#endif
