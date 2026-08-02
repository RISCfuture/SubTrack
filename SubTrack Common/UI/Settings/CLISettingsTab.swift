import SwiftUI

/**
 Installs the bundled `subtrack` command-line tool onto the user's `PATH` and
 reports its status, with a Terminal escape hatch for privileged folders.
 */
struct CLISettingsTab: View {
  @Environment(AppEnvironment.self)
  private var env
  @State private var installer = CLIInstaller()

  var body: some View {
    Form {
      Section {
        Text(
          "`subtrack` — slim videos from Terminal. Requires ffmpeg on your PATH, or pass `--ffmpeg`."
        )
        .font(.callout)
        .foregroundStyle(.secondary)
      }
      if env.featureFlags.isAppStoreBuild {
        Section {
          HStack(spacing: 6) {
            Label(
              "Installing the command-line tool is available in the downloadable version.",
              systemImage: "apple.terminal"
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            FullVersionHelpLink()
          }
        }
      } else {
        Section {
          CLIStatusRow(installer: installer)
          HStack {
            Button(LocalizedStringResource("Install…", bundle: #bundle)) { installer.install() }
              .accessibilityIdentifier("settings.cliInstall")
            Button(LocalizedStringResource("Copy Install Command", bundle: #bundle)) {
              installer.copyInstallCommand()
            }
            .accessibilityIdentifier("settings.cliCopyCommand")
          }
          .disabled(installer.embeddedCLI_URL == nil)
        }
        if case .needsElevation(let command) = installer.status {
          CLIElevationCallout(command: command) { installer.copyToPasteboard(command) }
        }
      }
    }
    .formStyle(.grouped)
    .settingsHelp(.commandLineTool, accessibilityIdentifier: "settings.cliHelp")
    .onAppear { installer.refreshStatus() }
  }
}

/**
 The CLI tab's status line: the installed path with a Reveal button, an error,
 or "Not installed".
 */
struct CLIStatusRow: View {
  let installer: CLIInstaller

  var body: some View {
    LabeledContent("Status") {
      switch installer.status {
        case .installed(let path):
          HStack {
            Text(path)
              .foregroundStyle(.secondary)
              .lineLimit(1)
              .truncationMode(.middle)
              .textSelection(.enabled)
            Button(LocalizedStringResource("Reveal", bundle: #bundle)) {
              installer.revealInFinder()
            }
            .accessibilityIdentifier("settings.cliReveal")
          }
        case let .failed(message, help):
          VStack(alignment: .leading, spacing: 2) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
              .foregroundStyle(.orange)
              .font(.callout)
            if let help {
              HelpTopicButton(anchor: help, accessibilityIdentifier: "settings.cliStatusHelp")
            }
          }
        default:
          Text("Not installed", bundle: #bundle).foregroundStyle(.secondary)
      }
    }
  }
}

/**
 Shown when the chosen install folder needs administrator access: the `sudo`
 command to run instead, with its own Copy button.
 */
struct CLIElevationCallout: View {
  let command: String
  let copy: () -> Void

  var body: some View {
    Section {
      Label(
        LocalizedStringResource(
          "That folder needs administrator access — run this instead.",
          bundle: #bundle
        ),
        systemImage: "lock"
      )
      .font(.callout)
      .foregroundStyle(.secondary)
      LabeledContent("Command") {
        HStack {
          Text(command)
            .font(.system(.callout, design: .monospaced))
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
          Button(LocalizedStringResource("Copy", bundle: #bundle), action: copy)
            .accessibilityIdentifier("settings.cliCopyElevation")
        }
      }
    }
  }
}

#if DEBUG
  #Preview("CLI — Not installed") {
    CLISettingsTab()
      .environment(settingsPreviewEnvironment(isAppStoreBuild: false))
      .frame(width: 480, height: 340)
  }

  #Preview("CLI — App Store (gated)") {
    CLISettingsTab()
      .environment(settingsPreviewEnvironment(isAppStoreBuild: true))
      .frame(width: 480, height: 340)
  }

  #Preview("CLI — Installed") {
    let installer = CLIInstaller()
    installer.status = .installed(path: "/usr/local/bin/subtrack")
    return Form { CLIStatusRow(installer: installer) }
      .formStyle(.grouped)
      .frame(width: 480, height: 340)
  }

  #Preview("CLI — Needs elevation") {
    Form {
      CLIElevationCallout(
        command:
          #"sudo cp "/Applications/SubTrack.app/Contents/Resources/subtrack" "/usr/local/bin/subtrack""#
      ) {}
    }
    .formStyle(.grouped)
    .frame(width: 480, height: 340)
  }

  #Preview("CLI Status — failed") {
    Form {
      CLIStatusRow(
        installer: {
          let installer = CLIInstaller()
          installer.status = .describing(
            CLIInstallError.copyFailed(detail: "Couldn’t write to /usr/local/bin")
          )
          return installer
        }()
      )
    }
    .formStyle(.grouped)
    .frame(width: 480, height: 200)
  }
#endif
