import SwiftUI

struct GroupNameSheet: View {
  let title: String
  let actionTitle: String
  let initialName: String
  let onSubmit: (String) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var name: String

  init(
    title: String,
    actionTitle: String,
    initialName: String = "",
    onSubmit: @escaping (String) -> Void
  ) {
    self.title = title
    self.actionTitle = actionTitle
    self.initialName = initialName
    self.onSubmit = onSubmit
    _name = State(initialValue: initialName)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 5) {
        Text(title)
          .font(.title2.weight(.semibold))
        Text("A group keeps its instruction files synchronized.")
          .foregroundStyle(.secondary)
      }

      TextField("Group name", text: $name)
        .textFieldStyle(.roundedBorder)
        .onSubmit(submit)

      HStack {
        Spacer()
        Button("Cancel") {
          dismiss()
        }
        .keyboardShortcut(.cancelAction)

        Button(actionTitle, action: submit)
          .buttonStyle(.glassProminent)
          .keyboardShortcut(.defaultAction)
          .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
    .padding(24)
    .frame(width: 420)
  }

  private func submit() {
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else {
      return
    }
    onSubmit(trimmedName)
    dismiss()
  }
}
