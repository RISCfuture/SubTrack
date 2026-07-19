import AppKit
import SwiftUI

/**
 A text field that shows recognized `{…}` placeholders as rounded tokens while
 everything around them stays editable text.

 Wraps `NSTokenField`, the only AppKit control with inline tokens. Its
 tokenizing character set is empty, so typed text never becomes a token by
 itself; a token appears when a placeholder reaches the field — typed, pasted,
 dropped, or written through the binding.
 */
struct TokenizedTextField: NSViewRepresentable {
  @Binding var segments: [OutputNameSegment]
  let placeholder: LocalizedStringResource
  let accessibilityIdentifier: String

  func makeNSView(context: Context) -> NSTokenField {
    let field = NSTokenField()
    field.delegate = context.coordinator
    field.tokenStyle = .rounded
    field.tokenizingCharacterSet = CharacterSet()
    field.placeholderString = String(localized: placeholder)
    field.font = .preferredFont(forTextStyle: .body)
    field.lineBreakMode = .byTruncatingTail
    field.setAccessibilityIdentifier(accessibilityIdentifier)
    field.setAccessibilityLabel(String(localized: "Output name format"))
    context.coordinator.push(segments, into: field)
    return field
  }

  func updateNSView(_ field: NSTokenField, context: Context) {
    context.coordinator.segments = $segments
    guard segments != context.coordinator.displayedSegments else { return }
    context.coordinator.push(segments, into: field)
  }

  func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTokenField, context _: Context)
    -> CGSize?
  {
    CGSize(
      width: proposal.width ?? nsView.intrinsicContentSize.width,
      height: nsView.intrinsicContentSize.height
    )
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(segments: $segments)
  }

  /**
   Translates between the field's represented objects — plain `String`s and
   ``TokenObject``s — and the ``OutputNameSegment`` list the binding carries.
   */
  @MainActor
  final class Coordinator: NSObject, NSTokenFieldDelegate {

    /**
     What the field is currently showing, so an edit the field itself made is
     never pushed back into it mid-typing.
     */
    private(set) var displayedSegments: [OutputNameSegment] = []

    var segments: Binding<[OutputNameSegment]>

    init(segments: Binding<[OutputNameSegment]>) {
      self.segments = segments
    }

    private static func representedObject(for segment: OutputNameSegment) -> Any {
      switch segment {
        case .text(let text): text
        case .token(let token): TokenObject(token: token)
      }
    }

    /**
     The segments a represented object stands for: a token object is one
     token, and a string is however it parses — which is how a placeholder
     that arrived as text becomes a token.
     */
    private static func parse(_ object: Any) -> [OutputNameSegment] {
      if let token = object as? TokenObject { return [.token(token.token)] }
      guard let text = object as? String else { return [] }
      return OutputNameFormat(template: text).segments
    }

    /**
     Whether a represented object is text that spells out a token, and so
     should be re-rendered as one.
     */
    private static func holdsPlaceholder(_ object: Any) -> Bool {
      object is TokenObject ? false : parse(object).contains(where: \.isToken)
    }

    /**
     Renders `segments` into the field and parks the insertion point at the
     end, so inserting a token leaves the user typing after it.
     */
    func push(_ segments: [OutputNameSegment], into field: NSTokenField) {
      displayedSegments = segments
      field.objectValue = segments.map(Self.representedObject)
      if let editor = field.currentEditor() {
        editor.selectedRange = NSRange(location: editor.string.count, length: 0)
      }
    }

    func controlTextDidChange(_ notification: Notification) {
      guard let field = notification.object as? NSTokenField else { return }
      let objects = field.objectValue as? [Any] ?? []
      let edited = objects.flatMap(Self.parse)
      displayedSegments = edited
      segments.wrappedValue = edited
      // Text that turned out to hold a placeholder is re-pushed so it reads as a
      // token straight away, which is what typing, pasting, or dropping one means.
      if objects.contains(where: Self.holdsPlaceholder) { push(edited, into: field) }
    }

    func tokenField(_: NSTokenField, displayStringForRepresentedObject object: Any)
      -> String?
    {
      (object as? TokenObject)?.token.title ?? object as? String
    }

    func tokenField(
      _: NSTokenField,
      styleForRepresentedObject object: Any
    ) -> NSTokenField.TokenStyle {
      object is TokenObject ? .rounded : .none
    }

    func tokenField(_: NSTokenField, editingStringForRepresentedObject object: Any)
      -> String?
    {
      (object as? TokenObject)?.token.placeholder ?? object as? String
    }

    func tokenField(_: NSTokenField, representedObjectForEditing editingString: String)
      -> Any?
    {
      let parsed = Self.parse(editingString)
      guard parsed.count == 1, case .token(let token) = parsed[0] else { return editingString }
      return TokenObject(token: token)
    }

    func tokenField(_: NSTokenField, readFrom pasteboard: NSPasteboard) -> [Any]? {
      guard let text = pasteboard.string(forType: .string) else { return nil }
      return Self.parse(text).map(Self.representedObject)
    }

    func tokenField(
      _: NSTokenField,
      writeRepresentedObjects objects: [Any],
      to pasteboard: NSPasteboard
    ) -> Bool {
      pasteboard.clearContents()
      return pasteboard.setString(
        OutputNameFormat(segments: objects.flatMap(Self.parse)).template,
        forType: .string
      )
    }
  }

  /// The represented object standing in for a token in the field.
  final class TokenObject: NSObject {
    let token: OutputNameToken

    init(token: OutputNameToken) {
      self.token = token
    }
  }
}

#if DEBUG
  /**
   The field beside the template its binding currently holds, so a preview shows
   both what the user sees and what round-trips back out through the format.
   */
  private struct FramedTokenizedField: View {
    @Binding var segments: [OutputNameSegment]

    var body: some View {
      VStack(alignment: .leading, spacing: 6) {
        TokenizedTextField(
          segments: $segments,
          placeholder: "name",
          accessibilityIdentifier: "preview.nameFormat"
        )
        Text(OutputNameFormat(segments: segments).template)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .padding()
      .frame(width: 320)
    }
  }

  #Preview("Tokenized Field — empty") {
    @Previewable @State var segments: [OutputNameSegment] = []
    FramedTokenizedField(segments: $segments)
  }

  #Preview("Tokenized Field — text only") {
    @Previewable @State var segments: [OutputNameSegment] = [.text("Archive copy")]
    FramedTokenizedField(segments: $segments)
  }

  #Preview("Tokenized Field — tokenized") {
    @Previewable @State var segments: [OutputNameSegment] = [
      .token(.originalName),
      .text(" (slimmed "),
      .token(.sequenceNumber),
      .text(")")
    ]
    FramedTokenizedField(segments: $segments)
  }
#endif
