import SwiftUI

struct CircleSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var name:          String
    @State private var archiveAfterDays: Int
    @State private var loading        = false
    @State private var error:         String?
    @State private var showRecipients = false

    init(circle: CareCircle) {
        _name          = State(initialValue: circle.name)
        _archiveAfterDays = State(initialValue: circle.archiveAfterDays)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Circle") {
                    TextField("Care Circle name", text: $name)
                    if let circle = appState.activeCircle {
                        LabeledContent("Care receivers",
                                   value: circle.recipientDisplaySummary.isEmpty
                                          ? "None yet — add one from Care Receiver Management"
                                          : circle.recipientDisplaySummary)
                    }
                    Button("Manage care receivers") {
                        showRecipients = true
                    }
                }
                Section("Completed Tasks") {
                    Stepper(value: $archiveAfterDays, in: 1...30) {
                        LabeledContent("Archive after", value: "\(archiveAfterDays) day\(archiveAfterDays == 1 ? "" : "s")")
                    }
                    Text("Completed and skipped tasks stay visible in the Completed section until this archive window ends.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let error {
                    Section { Text(error).foregroundColor(.red).font(.caption) }
                }
            }
            .navigationTitle("Care Circle Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty
                                  || loading)
                }
            }
        }
        .sheet(isPresented: $showRecipients) {
            RecipientManagementView()
                .environmentObject(appState)
        }
        .careLoopBrandBanner()
    }

    private func save() async {
        guard let circle = appState.activeCircle else { return }
        loading = true
        error   = nil
        do {
            let updated = try await APIClient.shared.updateCircle(
                id:            circle.id,
                name:          name.trimmingCharacters(in: .whitespaces),
                recipientName: nil,
                archiveAfterDays: archiveAfterDays
            )
            appState.attachCircle(updated)
            dismiss()
        } catch { self.error = error.localizedDescription }
        loading = false
    }
}
