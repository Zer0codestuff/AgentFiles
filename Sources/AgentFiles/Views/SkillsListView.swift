import SwiftUI

struct SkillsListView: View {
  let store: AgentFilesStore
  let searchText: String

  @State private var filter = SkillFilter.all

  var body: some View {
    VStack(spacing: 0) {
      header

      Divider()

      if store.skills.isEmpty {
        ContentUnavailableView {
          Label(
            store.isScanningSkills ? "Scanning Skills" : "No Skills",
            systemImage: "sparkles"
          )
        } description: {
          Text("Skills are folders with a SKILL.md file inside each agent's skills folder.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if filteredSkills.isEmpty {
        ContentUnavailableView.search(text: searchText)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        List(selection: selection) {
          ForEach(filteredSkills) { skill in
            SkillRow(
              skill: skill,
              state: store.skillState(for: skill),
              isTracked: store.trackedSkill(named: skill.name) != nil,
              locations: store.availableSkillLocations
            )
            .tag(skill.name)
          }
        }
        .listStyle(.inset)
      }
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 3) {
          Text("Skills")
            .font(.title3.weight(.semibold))
          Text("\(store.skills.count) skills in \(store.availableSkillLocations.count) folders")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        if store.isScanningSkills {
          ProgressView()
            .controlSize(.small)
        }
        Button("Rescan", systemImage: "arrow.clockwise") {
          store.scheduleSkillScan(delay: .zero)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.glass)
        .help("Scan skill folders again")
      }

      Picker("Filter", selection: $filter) {
        ForEach(SkillFilter.allCases) { filter in
          Text(filter.title).tag(filter)
        }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
    }
    .padding(16)
  }

  private var filteredSkills: [SkillRecord] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    return store.skills.filter { skill in
      let matchesQuery =
        query.isEmpty
        || skill.name.localizedStandardContains(query)
        || skill.summary.localizedStandardContains(query)
      guard matchesQuery else {
        return false
      }

      switch filter {
      case .all:
        return true
      case .attention:
        return store.skillsNeedingAttention.contains { $0.name == skill.name }
      case .tracked:
        return store.trackedSkill(named: skill.name) != nil
      }
    }
  }

  private var selection: Binding<String?> {
    Binding(
      get: { store.selectedSkillName },
      set: { store.selectedSkillName = $0 }
    )
  }
}

private enum SkillFilter: String, CaseIterable, Identifiable {
  case all
  case attention
  case tracked

  var id: String { rawValue }

  var title: String {
    switch self {
    case .all:
      "All"
    case .attention:
      "Differs"
    case .tracked:
      "Kept in Sync"
    }
  }
}

private struct SkillRow: View {
  let skill: SkillRecord
  let state: SkillSyncState
  let isTracked: Bool
  let locations: [SkillLocation]

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack(spacing: 6) {
        Text(skill.name)
          .fontWeight(.medium)
          .lineLimit(1)
        if isTracked {
          Image(systemName: "link")
            .font(.caption)
            .foregroundStyle(.secondary)
            .help("Kept in sync")
        }
        Spacer(minLength: 6)
        SkillStateLabel(state: state, compact: true)
      }

      if !skill.summary.isEmpty {
        Text(skill.summary)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }

      HStack(spacing: 4) {
        ForEach(locations) { location in
          let installed = skill.installation(in: location.id) != nil
          Circle()
            .fill(installed ? location.tint : Color.clear)
            .overlay(Circle().strokeBorder(location.tint.opacity(installed ? 0 : 0.45)))
            .frame(width: 7, height: 7)
            .help(installed ? "In \(location.title)" : "Not in \(location.title)")
        }
      }
      .padding(.top, 1)
    }
    .padding(.vertical, 4)
  }
}

struct SkillStateLabel: View {
  let state: SkillSyncState
  var compact = false

  var body: some View {
    if compact {
      Image(systemName: systemImage)
        .font(.caption)
        .foregroundStyle(color)
        .help(title)
    } else {
      GlassTag(title: title, systemImage: systemImage, tint: color)
    }
  }

  private var title: String {
    switch state {
    case .synchronized:
      "Available everywhere"
    case .missing(let count):
      count == 1 ? "Missing for 1 agent" : "Missing for \(count) agents"
    case .differs(let count):
      "\(count) different versions"
    case .conflict:
      "Sync paused"
    }
  }

  private var systemImage: String {
    switch state {
    case .synchronized:
      "checkmark.circle.fill"
    case .missing:
      "circle.dashed"
    case .differs:
      "arrow.triangle.branch"
    case .conflict:
      "exclamationmark.triangle.fill"
    }
  }

  private var color: Color {
    switch state {
    case .synchronized:
      .green
    case .missing:
      .secondary
    case .differs:
      .orange
    case .conflict:
      .red
    }
  }
}
