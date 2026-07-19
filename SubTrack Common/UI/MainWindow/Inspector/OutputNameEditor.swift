import SwiftUI

/**
 Editor for an ``OutputNameFormat``: a tokenized field and the tokens that can
 be dragged or clicked into it. Carries no opinion about whose format it is, so
 both a queue's and a preset's are edited the same way.
 */
struct OutputNameFormatField: View {
  @Binding var format: OutputNameFormat
  let accessibilityIdentifier: String

  /**
   Outlines the field in red — the queue's editor sets this when the format
   would have a run destroy a file.
   */
  var isInvalid = false

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      TokenizedTextField(
        segments: segments,
        placeholder: "name",
        accessibilityIdentifier: accessibilityIdentifier
      )
      .overlay {
        RoundedRectangle(cornerRadius: 6)
          .strokeBorder(.red)
          .opacity(isInvalid ? 1 : 0)
      }
      TokenPalette(append: append)
    }
  }

  private var segments: Binding<[OutputNameSegment]> {
    Binding(
      get: { format.segments },
      set: { format = OutputNameFormat(segments: $0) }
    )
  }

  private func append(_ token: OutputNameToken) {
    format = OutputNameFormat(segments: format.segments + [.token(token)])
  }
}

/**
 The queue's own output-name format: the shared field, a preview of the name it
 produces against a real queued file, and any conflict that format causes.
 */
struct OutputNameEditor: View {
  @Environment(AppEnvironment.self)
  private var env

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      OutputNameFormatField(
        format: format,
        accessibilityIdentifier: "rules.nameFormat",
        isInvalid: !conflicts.isEmpty
      )
      Text(preview)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.middle)
      ForEach(conflicts, id: \.self) { conflict in
        ConflictWarning(conflict: conflict, accessibilityIdentifier: "rules.nameFormatConflict")
      }
    }
  }

  private var conflicts: [OutputNameConflict] { env.queue.outputNameConflicts }

  private var naming: OutputNameFormat { env.queue.settings.naming }

  /**
   The name the format currently produces, shown against the first queued file
   when there is one so the user sees the real answer rather than a stand-in.
   */
  private var preview: String {
    guard let item = env.queue.items.first else {
      return String(localized: "Names look like “\(naming.sampleFileName)”")
    }
    return String(
      localized: "\(item.displayName) → \(naming.fileName(for: item.sourceURL, position: 1))"
    )
  }

  /**
   Writes through the queue's settings so the edit restates every pending
   item's output path and persists.
   */
  private var format: Binding<OutputNameFormat> {
    Binding(
      get: { naming },
      set: { env.queue.settings.editNaming($0) }
    )
  }
}

/**
 The tokens available to the format. Each can be dragged into the field or
 clicked to append, so the format is reachable without a pointer.
 */
private struct TokenPalette: View {
  let append: (OutputNameToken) -> Void

  var body: some View {
    HStack(spacing: 6) {
      ForEach(OutputNameToken.allCases, id: \.self) { token in
        TokenChip(token: token, append: append)
      }
      Spacer(minLength: 0)
    }
  }
}

private struct TokenChip: View {
  let token: OutputNameToken
  let append: (OutputNameToken) -> Void

  var body: some View {
    Button {
      append(token)
    } label: {
      Text(token.title)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(.quaternary, in: Capsule())
    }
    .buttonStyle(.plain)
    .draggable(token.placeholder)
    .help("Drag into the name, or click to add it at the end")
    .accessibilityIdentifier("rules.nameToken.\(token.rawValue)")
  }
}

#if DEBUG
  /**
   Two files that share a name but not a folder, sent to one destination — the
   arrangement the default format collides on.
   */
  @MainActor
  private func collidingEnvironment() -> AppEnvironment {
    let env = PreviewSupport.environment(items: [
      PreviewSupport.ItemSpec(name: "Show.mkv", folder: "/Movies/A"),
      PreviewSupport.ItemSpec(name: "Show.mkv", folder: "/Movies/B")
    ])
    env.queue.settings.destination.setDestination(URL(filePath: "/Users/Shared/Slimmed"))
    return env
  }

  /**
   The Rules tab's framing around the editor: a grouped form section at the
   inspector's density, so the tokens and preview line size as they do in the
   tab rather than at full body size.
   */
  private struct FramedNameEditor: View {
    var body: some View {
      Form {
        Section("Output name") { OutputNameEditor() }
      }
      .formStyle(.grouped)
      .controlSize(.small)
      .frame(width: 320)
    }
  }

  #Preview("Output Name — empty queue") {
    FramedNameEditor()
      .environment(PreviewSupport.environment())
  }

  #Preview("Output Name — with a file") {
    FramedNameEditor()
      .environment(PreviewSupport.environment(items: [PreviewSupport.ItemSpec(name: "Film.mkv")]))
  }

  #Preview("Output Name — conflicting") {
    FramedNameEditor()
      .environment(collidingEnvironment())
  }
#endif
