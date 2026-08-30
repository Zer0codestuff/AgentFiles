import SwiftUI

struct ContentView: View {
  let store: AgentFilesStore

  @State private var columnVisibility = NavigationSplitViewVisibility.all
  @State private var searchText = ""
  @State private var showingNewGroup = false
  @State private var groupToRename: SyncGroup?

  var body: some View {
    NavigationSplitView(columnVisibility: $columnVisibility) {
      GroupsSidebarView(
        store: store,
        onNewGroup: { showingNewGroup = true },
        onRenameGroup: { groupToRename = $0 }
      )
      .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
    } content: {
      ManagedFilesView(
        store: store,
        searchText: searchText,
        onAddFiles: addFiles
      )
      .navigationSplitViewColumnWidth(min: 250, ideal: 310, max: 420)
    } detail: {
      FileEditorView(store: store, fileID: store.selectedFileID)
        .frame(minWidth: 420)
    }
    .searchable(text: $searchText, placement: .toolbar, prompt: "Find files")
    .toolbar(removing: .title)
    .toolbar {
      ToolbarItemGroup(placement: .primaryAction) {
        Button {
          store.setAutomaticSyncEnabled(!store.automaticSyncEnabled)
        } label: {
          Label(
            store.automaticSyncEnabled ? "Pause Automatic Sync" : "Enable Automatic Sync",
            systemImage: store.automaticSyncEnabled ? "bolt.fill" : "bolt.slash"
          )
        }
        .help(store.automaticSyncEnabled ? "Pause automatic sync" : "Enable automatic sync")

        Menu {
          Button("New Sync Group", systemImage: "folder.badge.plus") {
            showingNewGroup = true
          }

          Button("Add Files", systemImage: "doc.badge.plus") {
            addFiles()
          }
          .disabled(store.selectedGroupID == nil)
        } label: {
          Label("Add", systemImage: "plus")
        }
        .help("Add a group or instruction files")
      }
    }
    .sheet(isPresented: $showingNewGroup) {
      GroupNameSheet(
        title: "New Sync Group",
        actionTitle: "Create",
        initialName: "Shared Instructions"
      ) { name in
        _ = store.createGroup(named: name)
      }
    }
    .sheet(item: $groupToRename) { group in
      GroupNameSheet(
        title: "Rename Sync Group",
        actionTitle: "Rename",
        initialName: group.name
      ) { name in
        store.renameGroup(id: group.id, to: name)
      }
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
  }

  private func addFiles() {
    guard let groupID = store.selectedGroupID else {
      store.notice = AppNotice(
        title: "Create a sync group first",
        message: "Files need a group before Agent Files can manage them."
      )
      return
    }

    let urls = OpenPanelService().chooseInstructionFiles()
    guard !urls.isEmpty else {
      return
    }
    store.addFiles(urls, to: groupID)
  }
}
