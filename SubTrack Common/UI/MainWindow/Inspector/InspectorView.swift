import SwiftUI

/**
 The trailing inspector, switching between the queue's keep-rules and the
 selected file's own overrides.
 */
struct InspectorView: View {
  @Environment(AppEnvironment.self)
  private var env

  var body: some View {
    @Bindable var ui = env.ui
    VStack(spacing: 0) {
      Picker(
        LocalizedStringResource("Inspector Mode", bundle: #bundle),
        selection: $ui.inspectorMode
      ) {
        Text("Rules", bundle: #bundle).tag(InspectorMode.rules)
        Text("Override", bundle: #bundle).tag(InspectorMode.override)
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .controlSize(.small)
      .padding()
      .accessibilityIdentifier("inspector.mode")
      Divider()

      // The tab has to claim the whole pane even when its content is short, or
      // the stack centres itself and the mode picker drifts down with it.
      Group {
        switch ui.inspectorMode {
          case .rules: RulesInspector()
          case .override: OverrideInspector()
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    // The pane is one addressable element, so a test can frame it — the mode
    // picker and the tab below it are otherwise siblings with nothing naming
    // the whole. `.contain` keeps every control inside it a queryable
    // descendant rather than collapsing them into one.
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("inspector.pane")
  }
}

#if DEBUG
  #Preview("Inspector — Rules") {
    let env = PreviewSupport.environment()
    env.ui.inspectorMode = .rules
    env.capabilities.setForPreview(.loaded(.previewSample))
    return InspectorView()
      .environment(env)
      .frame(width: 300, height: 560)
  }

  #Preview("Inspector — Override (no selection)") {
    let env = PreviewSupport.environment()
    env.ui.inspectorMode = .override
    return InspectorView()
      .environment(env)
      .frame(width: 300, height: 560)
  }

  #Preview("Inspector — Override (file)") {
    let env = PreviewSupport.environment(items: [
      PreviewSupport.ItemSpec(
        name: "Film.mkv",
        status: .ready,
        container: PreviewSupport.container()
      )
    ])
    env.ui.inspectorMode = .override
    env.queue.selection = [env.queue.items[0].id]
    return InspectorView()
      .environment(env)
      .frame(width: 300, height: 560)
  }
// The Override tab's orange "mismatch banner" keys off env.queue.encoderCapabilities,
// which is read-only and defaults to .full — it can't be triggered from a preview
// without changing production code, so no preview exercises it.
#endif
