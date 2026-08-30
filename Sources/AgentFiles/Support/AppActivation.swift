import AppKit

enum AppActivation {
  @MainActor
  static func bringForward() {
    NSApp.activate(ignoringOtherApps: true)
    DispatchQueue.main.async {
      NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
    }
  }
}
