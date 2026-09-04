import Foundation
import Testing

@testable import SubTrack_Common

@Suite
struct CLIInstallerTests {

  @Test
  func `quotes bundle path with spaces`() {
    let source = URL(fileURLWithPath: "/Applications/My App.app/Contents/Resources/subtrack")
    let destination = URL(fileURLWithPath: "/opt/tools", isDirectory: true)
    let command = CLIInstaller.installCommand(source: source, destinationDirectory: destination)
    #expect(
      command
        == #"sudo cp "/Applications/My App.app/Contents/Resources/subtrack" "/opt/tools/subtrack""#
    )
  }

  @Test
  func `defaults destination to /usr/local/bin`() {
    let source = URL(fileURLWithPath: "/Applications/SubTrack.app/Contents/Resources/subtrack")
    let command = CLIInstaller.installCommand(source: source)
    #expect(
      command
        == #"sudo cp "/Applications/SubTrack.app/Contents/Resources/subtrack" "/usr/local/bin/subtrack""#
    )
  }
}
