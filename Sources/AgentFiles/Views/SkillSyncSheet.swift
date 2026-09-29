import SwiftUI

struct SkillSyncSheet: View {
  let store: AgentFilesStore
  let plan: SkillSyncPlan

  @Environment(\.dismiss) private var dismiss
  @State private var isApplying = false

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 14) {
        if let source {
          HarnessGlyph(location: source, size: 42)
        }
        VStack(alignment: .leading, spacing: 4) {
          Text("Sync \(plan.skillName)")
            .font(.title2.weight(.semibold))
          Text(summary)
            .foregroundStyle(.secondary)
        }
        Spacer()
      }
      .padding(22)

      Divider()

      ScrollView {
        VStack(spacing: 12) {
          ForEach(plan.targets) { target in
            targetCard(target)
          }
        }
        .padding(20)
      }

      Divider()

      HStack {
        Label(
          "Existing folders are backed up before writing.",
          systemImage: "externaldrive.badge.checkmark"
        )
        .font(.caption)
        .foregroundStyle(.secondary)

        Spacer()

        Button("Cancel") {
          dismiss()
        }
        .keyboardShortcut(.cancelAction)

        Button(isApplying ? "Syncing…" : "Sync") {
          isApplying = true
          Task {
            let applied = await store.applySkillPlan(plan)
            isApplying = false
            if applied {
              dismiss()
            }
          }
        }
        .buttonStyle(.glassProminent)
        .keyboardShortcut(.defaultAction)
        .disabled(plan.changedTargets.isEmpty || isApplying)
      }
      .padding(16)
    }
    .frame(width: 600, height: 520)
  }

  private var source: SkillLocation? {
    store.skillLocation(id: plan.sourceLocationID)
  }

  private var summary: String {
    let count = plan.changedTargets.count
    let title = source?.title ?? "selected"
    if count == 0 {
      return "Every copy already matches the \(title) version."
    }
    return count == 1
      ? "Copy the \(title) version to 1 location."
      : "Copy the \(title) version to \(count) locations."
  }

  private func targetCard(_ target: SkillSyncTarget) -> some View {
    let location = store.skillLocation(id: target.locationID)
    return VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        if let location {
          HarnessGlyph(location: location, size: 28)
        }
        VStack(alignment: .leading, spacing: 2) {
          Text(location?.title ?? target.locationID)
            .font(.headline)
          Text(PathFormatter.compact(target.directory.path))
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
        }
        Spacer()
        GlassTag(
          title: target.existed ? changeSummary(target) : "New folder",
          tint: target.existed ? nil : .green
        )
      }

      if !target.changes.isEmpty {
        VStack(alignment: .leading, spacing: 4) {
          ForEach(target.changes.prefix(10), id: \.self) { change in
            Label {
              Text(change.path)
                .font(.caption.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
            } icon: {
              Image(systemName: symbol(for: change.kind))
                .foregroundStyle(color(for: change.kind))
            }
          }
          if target.changes.count > 10 {
            Text("and \(target.changes.count - 10) more")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        .padding(.leading, 38)
      }
    }
    .padding(14)
    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
  }

  private func changeSummary(_ target: SkillSyncTarget) -> String {
    let count = target.changes.count
    return count == 0 ? "No change" : count == 1 ? "1 file changes" : "\(count) files change"
  }

  private func symbol(for kind: SkillFileChange.Kind) -> String {
    switch kind {
    case .added:
      "plus.circle.fill"
    case .modified:
      "pencil.circle.fill"
    case .removed:
      "minus.circle.fill"
    }
  }

  private func color(for kind: SkillFileChange.Kind) -> Color {
    switch kind {
    case .added:
      .green
    case .modified:
      .orange
    case .removed:
      .red
    }
  }
}
