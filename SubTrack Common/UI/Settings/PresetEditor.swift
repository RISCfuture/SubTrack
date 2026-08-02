import SwiftUI

/**
 One preset's editable name and rules, plus the delete that removes it. Every
 edit is written straight through to the store, so there is nothing to save.
 */
struct PresetEditor: View {
  /// Keeps the delete row's button aligned with the grouped form's own insets.
  private static let deleteRowInsets = EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)

  @Environment(AppEnvironment.self)
  private var env
  let preset: Preset

  /// Called after the preset is deleted, so the list can drop its selection.
  let onDelete: () -> Void

  @State private var isConfirmingDelete = false

  var body: some View {
    VStack(spacing: 0) {
      Form {
        Section {
          TextField("Name", text: name)
            .accessibilityIdentifier("settings.presetName")
        }

        Section("Output name") {
          OutputNameFormatField(
            format: naming,
            accessibilityIdentifier: "settings.presetNameFormat"
          )
          InspectorCaption("Names look like “\(preset.naming.sampleFileName)”")
        }

        SlimRulesEditor(rules: rules)
      }
      .formStyle(.grouped)

      Divider()

      // Deleting isn't a setting, so it sits below the form rather than as a row
      // among the rules it would take with it.
      HStack {
        Spacer()
        Button {
          isConfirmingDelete = true
        } label: {
          Text("Delete Preset", bundle: #bundle).foregroundStyle(.red)
        }
        .accessibilityIdentifier("settings.deletePreset")
      }
      .padding(Self.deleteRowInsets)
    }
    .confirmationDialog(
      "Delete “\(preset.name)”?",
      isPresented: $isConfirmingDelete,
      titleVisibility: .visible
    ) {
      Button(LocalizedStringResource("Delete", bundle: #bundle), role: .destructive) { delete() }
      Button(LocalizedStringResource("Cancel", bundle: #bundle), role: .cancel) {}
    } message: {
      Text("Queues already using these rules keep them.", bundle: #bundle)
    }
  }

  private var name: Binding<String> {
    edited(\.name)
  }

  private var rules: Binding<SlimRules> {
    edited(\.rules)
  }

  private var naming: Binding<OutputNameFormat> {
    edited(\.naming)
  }

  /**
   A binding onto one of the preset's fields that writes the whole edited
   preset back to the store.
   */
  private func edited<Value>(_ keyPath: WritableKeyPath<Preset, Value>) -> Binding<Value> {
    Binding(
      get: { preset[keyPath: keyPath] },
      set: { newValue in
        var edited = preset
        edited[keyPath: keyPath] = newValue
        env.presets.save(edited)
      }
    )
  }

  private func delete() {
    env.presets.delete(preset)
    onDelete()
  }
}

#if DEBUG
  #Preview("Preset Editor") {
    let env = settingsPreviewEnvironment(isAppStoreBuild: false)
    return PresetEditor(preset: env.presets.presets.first ?? Preset.starters[0]) {}
      .environment(env)
      .frame(width: 450, height: 420)
  }
#endif
