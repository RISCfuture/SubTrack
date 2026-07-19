import SwiftUI

/**
 The active-preset menu plus save. Used in the inspector and the toolbar.

 Which preset is "active" is decided by what the queue's rules *are*, not by
 what was last applied: a preset the user has since edited away from stops
 being shown, and rules edited back into agreement with one show it again.
 */
struct PresetMenu: View {
  @Environment(AppEnvironment.self)
  private var env

  /**
   Whether the menu fills the width it is given, as it does heading the Rules
   tab. The toolbar wants it sized to its own label instead.
   */
  var expands = false

  /**
   Distinguishes this instance from the app's other one — the inspector and the
   toolbar both show this control, and a test driving one must not land on the
   other.
   */
  var accessibilityIdentifier = "presetMenu"

  @State private var isNaming = false
  @State private var draftName = ""

  var body: some View {
    Group {
      // Heading the Rules tab, the menu is a borderless row filling the width it
      // is given. In the toolbar it keeps the system menu style, which sizes the
      // item like the toolbar's other buttons and spaces the icon from the
      // disclosure chevron — spacing the borderless style crowds and no padding
      // can widen.
      if expands {
        PresetMenuControl(beginNaming: beginNaming)
          .menuStyle(.borderlessButton)
          .frame(maxWidth: .infinity, alignment: .leading)
      } else {
        PresetMenuControl(beginNaming: beginNaming)
      }
    }
    .accessibilityIdentifier(accessibilityIdentifier)
    .alert("Save Preset", isPresented: $isNaming) {
      TextField("Preset name", text: $draftName)
        .accessibilityIdentifier("presetName")
      Button("Cancel", role: .cancel) {}
      Button("Save") { save(named: draftName) }
        .disabled(trimmedDraftName.isEmpty)
    } message: {
      Text("Save the current rules and output name under a name you can apply to any queue.")
    }
  }

  private var trimmedDraftName: String {
    draftName.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Opens the name prompt on a suggestion the user can accept or type over.
  private func beginNaming() {
    draftName = String(localized: "My Preset \(env.presets.presets.count + 1, format: .number)")
    isNaming = true
  }

  /**
   Saves the queue's current rules and name format under `name`, and makes the
   queue's own active preset the one just saved.
   */
  private func save(named name: String) {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    let preset = Preset(
      id: UUID(),
      name: trimmed,
      rules: env.rules.rules,
      naming: env.queue.settings.naming
    )
    env.presets.save(preset)
    env.queue.settings.apply(preset)
  }
}

/**
 The menu itself: the saved presets, a checkmark on the one the queue's rules
 match, and the item that starts saving the current rules as a new preset.
 */
private struct PresetMenuControl: View {
  @Environment(AppEnvironment.self)
  private var env

  /// Called by the **Save Current as Preset…** item.
  let beginNaming: () -> Void

  var body: some View {
    Menu {
      ForEach(env.presets.presets) { preset in
        Button {
          env.queue.settings.apply(preset)
        } label: {
          if preset == activePreset {
            Label(preset.name, systemImage: "checkmark")
          } else {
            Text(preset.name)
          }
        }
      }
      Divider()
      Button("Save Current as Preset…") { beginNaming() }
    } label: {
      Label(activeName, systemImage: "slider.horizontal.3")
    }
  }

  /**
   The preset the queue's current settings *are*, or `nil` when they match
   none — which is what the menu reports as a new preset.
   */
  private var activePreset: Preset? {
    env.presets.presets.first {
      $0.rules == env.rules.rules && $0.naming == env.queue.settings.naming
    }
  }

  private var activeName: String {
    activePreset?.name ?? String(localized: "(New Preset)")
  }
}

#if DEBUG
  #Preview("Preset Menu — matches a preset") {
    Form {
      Section("Preset") {
        PresetMenu()
      }
    }
    .formStyle(.grouped)
    .environment(PreviewSupport.environment())
    .frame(width: 300)
  }

  #Preview("Preset Menu — matches none") {
    let env = PreviewSupport.environment()
    env.queue.settings.editRules { $0.languages = ["eng", "fra", "deu"] }
    return Form {
      Section("Preset") {
        PresetMenu()
      }
    }
    .formStyle(.grouped)
    .environment(env)
    .frame(width: 300)
  }
#endif
