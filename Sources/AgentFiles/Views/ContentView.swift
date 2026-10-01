import AppKit
import SwiftUI

struct ContentView: View {
  let store: AgentFilesStore

  var body: some View {
    NavigationSplitView {
      SidebarView(store: store)
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
    } detail: {
      switch store.selection {
      case .workspace(let id):
        if let workspace = store.workspace(id: id) {
          WorkspaceView(store: store, workspace: workspace)
            .id(workspace.id)
        }
      case .skills:
        SkillsView(store: store)
      case nil:
        ContentUnavailableView("Select Instructions", systemImage: "doc.text")
      }
    }
    .frame(minWidth: 860, minHeight: 540)
    .toolbar {
      ToolbarItem(placement: .automatic) {
        Button {
          store.showsSync = true
        } label: {
          Label("Sync", systemImage: store.syncError != nil || !store.syncConflicts.isEmpty
            ? "exclamationmark.icloud" : "icloud")
        }
        .help(store.syncStatus)
      }
    }
    .sheet(isPresented: Binding(get: { store.showsSync }, set: { store.showsSync = $0 })) {
      InstructionSyncView(store: store)
    }
    .alert(
      store.notice?.title ?? "",
      isPresented: Binding(
        get: { store.notice != nil },
        set: { if !$0 { store.notice = nil } }
      ),
      presenting: store.notice
    ) { _ in
      Button("OK") {
        store.notice = nil
      }
    } message: { notice in
      Text(notice.message)
    }
    .task {
      store.start()
    }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      store.refreshFiles()
      store.scheduleInstructionSync()
    }
  }
}
