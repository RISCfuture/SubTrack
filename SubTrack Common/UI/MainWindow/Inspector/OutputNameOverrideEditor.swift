import SwiftUI

/**
 Names one file's output: either the queue's own format, or a name the user
 gives this file alone. A named file still takes its turn in the queue, so the
 `{n}` every other file is numbered by doesn't shift when one is renamed.
 */
struct OutputNameOverrideEditor: View {
  @Environment(AppEnvironment.self)
  private var env
  let item: QueueItem

  var body: some View {
    InspectorGroup {
      Picker("File name", selection: usesCustomName) {
        Text("Use default name")
          .tag(false)
          .accessibilityIdentifier("override.useDefaultName")
        Text("Use custom name:")
          .tag(true)
          .accessibilityIdentifier("override.useCustomName")
      }
      .pickerStyle(.radioGroup)
      .labelsHidden()
      .accessibilityIdentifier("override.fileNameMode")

      // Sized a step above the rest of the tab: the name is the one thing here
      // the user types rather than picks, and at the form's own size it reads as
      // another line of caption.
      TextField("File name", text: customName, prompt: Text(defaultBaseName))
        .labelsHidden()
        .textFieldStyle(.roundedBorder)
        .controlSize(.regular)
        .disabled(item.customName == nil)
        .accessibilityIdentifier("override.customName")

      Text("Saves as “\(item.outputURL.lastPathComponent)”")
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.middle)

      ForEach(conflicts, id: \.self) { conflict in
        ConflictWarning(conflict: conflict, accessibilityIdentifier: "override.nameConflict")
      }
    }
  }

  /**
   The ways the queue would destroy a file that this one is caught up in, so a
   collision the user just created is reported where they created it.
   */
  private var conflicts: [OutputNameConflict] {
    env.queue.outputNameConflicts.filter { $0.sources.contains(item.sourceURL) }
  }

  /**
   The name the queue's format gives this file, without its extension — what
   the field starts from when the user takes the name over.
   */
  private var defaultBaseName: String {
    URL(filePath: env.queue.defaultOutputName(for: item))
      .deletingPathExtension()
      .lastPathComponent
  }

  private var customName: Binding<String> {
    Binding(
      get: { item.customName ?? "" },
      set: { env.queue.setCustomName($0, for: item) }
    )
  }

  /**
   Taking the name over seeds it with the name the file already has, so
   choosing to rename never renames anything on its own.
   */
  private var usesCustomName: Binding<Bool> {
    Binding(
      get: { item.customName != nil },
      set: { isCustom in
        env.queue.setCustomName(isCustom ? defaultBaseName : nil, for: item)
      }
    )
  }
}

#if DEBUG
  /**
   One queued file, optionally already renamed, as the Override tab hands the
   editor.
   */
  @MainActor
  private func namedEnvironment(customName: String? = nil) -> AppEnvironment {
    let env = PreviewSupport.environment(items: [PreviewSupport.ItemSpec(name: "Film.mkv")])
    if let customName { env.queue.setCustomName(customName, for: env.queue.items[0]) }
    return env
  }

  /**
   Two files that share a name but not a folder, sent to one destination, so the
   selected file's output collides with another queued file's.
   */
  @MainActor
  private func collidingNameEnvironment() -> AppEnvironment {
    let env = PreviewSupport.environment(items: [
      PreviewSupport.ItemSpec(name: "Show.mkv", folder: "/Movies/A"),
      PreviewSupport.ItemSpec(name: "Show.mkv", folder: "/Movies/B")
    ])
    env.queue.settings.destination.setDestination(URL(filePath: "/Users/Shared/Slimmed"))
    return env
  }

  /**
   The Override tab's framing around the editor: a grouped form section at the
   inspector's density, so the field and caption size as they do in the tab.
   */
  private struct FramedNameOverrideEditor: View {
    @Environment(AppEnvironment.self)
    private var env

    var body: some View {
      Form {
        Section("File name") {
          OutputNameOverrideEditor(item: env.queue.items[0])
        }
      }
      .formStyle(.grouped)
      .controlSize(.small)
      .frame(width: 320)
    }
  }

  #Preview("Name Override — default name") {
    FramedNameOverrideEditor()
      .environment(namedEnvironment())
  }

  #Preview("Name Override — custom name") {
    FramedNameOverrideEditor()
      .environment(namedEnvironment(customName: "Film (director’s cut)"))
  }

  #Preview("Name Override — conflicting") {
    FramedNameOverrideEditor()
      .environment(collidingNameEnvironment())
  }
#endif
