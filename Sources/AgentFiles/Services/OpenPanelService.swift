import AppKit
import Foundation

@MainActor
struct OpenPanelService {
  func chooseProjectFolder() -> URL? {
    let panel = NSOpenPanel()
    panel.title = "Add project"
    panel.message = "Choose a project folder. Agent Files syncs its AGENTS.md and CLAUDE.md."
    panel.prompt = "Add Project"
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = false

    return panel.runModal() == .OK ? panel.url : nil
  }
}
