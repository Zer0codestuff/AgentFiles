import AppKit
import Foundation

@MainActor
struct OpenPanelService {
  func chooseInstructionFiles() -> [URL] {
    let panel = NSOpenPanel()
    panel.title = "Add instruction files"
    panel.message = "Choose UTF-8 text files to add to this sync group."
    panel.prompt = "Add"
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = true
    panel.resolvesAliases = true
    panel.showsHiddenFiles = true

    return panel.runModal() == .OK ? panel.urls : []
  }
}
