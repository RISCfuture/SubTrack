import SwiftUI

/**
 Editor for the selected queue's keep-rules, headed by the preset menu. A
 preset seeds the rules; editing them here leaves the queue on rules that match
 no preset until the user saves them as one.
 */
struct RulesInspector: View {
  @Environment(AppEnvironment.self)
  private var env

  var body: some View {
    InspectorForm {
      PresetMenu(expands: true)
    } content: {
      Section {
        OutputNameEditor()
      } header: {
        InspectorSectionHeader(
          title: "Output name",
          help:
            "Tokens stand in for each file’s own details. The original extension is always kept."
        )
      }

      SlimRulesEditor(rules: rules)
    }
  }

  /**
   Writes rule edits through the owning queue's settings so each one
   revalidates compatibility and persists — never through a raw `env.rules`
   mutation, which wouldn't notify the queue.
   */
  private var rules: Binding<SlimRules> {
    Binding(
      get: { env.rules.rules },
      set: { edited in env.queue.settings.editRules { $0 = edited } }
    )
  }
}

#if DEBUG
  #Preview("Rules Inspector") {
    let env = PreviewSupport.environment()
    env.capabilities.setForPreview(.loaded(.previewSample))
    return RulesInspector()
      .environment(env)
      .frame(width: 320, height: 620)
  }
#endif
