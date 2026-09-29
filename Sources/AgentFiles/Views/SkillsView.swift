import SwiftUI

/// The secondary Skills library: a list of skills beside the selected skill.
struct SkillsView: View {
  let store: AgentFilesStore

  @State private var searchText = ""

  var body: some View {
    HStack(spacing: 0) {
      SkillsListView(store: store, searchText: searchText)
        .frame(width: 320)
      Divider()
      SkillDetailView(store: store, skillName: store.selectedSkillName)
        .frame(maxWidth: .infinity)
    }
    .navigationTitle("Skills")
    .searchable(text: $searchText, placement: .toolbar, prompt: "Find skills")
  }
}
