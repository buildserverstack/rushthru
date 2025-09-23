import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var csv: CSVViewModel
    @EnvironmentObject private var activity: ActivityLogViewModel
    @EnvironmentObject private var locations: LocationsViewModel
    @State private var exportText: String = ""
    @State private var newStoreName: String = ""
    @State private var storeStatus: String = ""
    @State private var importText: String = ""
    @State private var importStatus: String = ""

    var body: some View {
        NavigationStack {
            Form {
                if !locations.stores.isEmpty {
                    Section("Store Filter") {
                        Picker("Active Store", selection: Binding(
                            get: { locations.selectedStoreID },
                            set: { locations.selectedStoreID = $0 }
                        )) {
                            Text("All Stores")
                                .tag(UUID?.none)
                            ForEach(locations.stores) { store in
                                Text(store.name)
                                    .tag(Optional(store.id))
                            }
                        }
                        .pickerStyle(.menu)
                        TextField("New store name", text: $newStoreName)
                        Button("Add Store") {
                            addStore()
                        }
                        .disabled(newStoreName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if locations.selectedStoreID != nil {
                            Button("Show All Stores") {
                                locations.selectedStoreID = nil
                                storeStatus = "Showing all stores"
                                clearStoreStatus(after: 2)
                            }
                        }
                        if !storeStatus.isEmpty {
                            Text(storeStatus)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("CSV Backup") {
                    Button("Export Inventory") {
                        exportText = csv.exportInventory()
                    }
                    if !exportText.isEmpty {
                        ShareLink(item: exportText)
                    }
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $importText)
                            .frame(minHeight: 120)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                        if importText.isEmpty {
                            Text("Paste inventory CSV here")
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                                .padding(.horizontal, 4)
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2))
                    )
                    .padding(.vertical, 4)
                    Button("Import Inventory") {
                        importInventory()
                    }
                    .disabled(importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if !importStatus.isEmpty {
                        Text(importStatus)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if !csv.lastValidationIssues.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Validation Issues")
                                .font(.footnote.weight(.semibold))
                            ForEach(csv.lastValidationIssues) { issue in
                                Text("• \(issue.message)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.top, 4)
                    }
                    if let summary = csv.lastImportSummary {
                        Text("Imported \(summary.importedItems) items")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Activity") {
                    Button("Compact Activity Log") {
                        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
                        activity.compact(olderThan: cutoff)
                    }
                    Text("Total entries: \(activity.entries.count)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func addStore() {
        let trimmed = newStoreName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task {
            let added = await locations.createStore(named: trimmed)
            await MainActor.run {
                storeStatus = added ? "Added \(trimmed)" : "Store already exists"
                if added { newStoreName = "" }
                clearStoreStatus(after: 2)
            }
        }
    }

    private func importInventory() {
        let payload = importText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !payload.isEmpty else { return }
        Task {
            do {
                try await csv.replaceInventory(with: payload)
                await MainActor.run {
                    importStatus = "Import complete"
                    importText = ""
                    clearImportStatus(after: 3)
                }
            } catch let error as CSVViewModel.CSVError {
                switch error {
                case .validationFailed(let issues):
                    await MainActor.run {
                        importStatus = issues.first?.message ?? "Validation failed"
                        clearImportStatus(after: 4)
                    }
                }
            } catch {
                await MainActor.run {
                    importStatus = error.localizedDescription
                    clearImportStatus(after: 4)
                }
            }
        }
    }

    private func clearStoreStatus(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            storeStatus = ""
        }
    }

    private func clearImportStatus(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            importStatus = ""
        }
    }
}

#Preview {
    let environment = AppEnvironment(preview: true)
    SettingsView()
        .environmentObject(environment.auth)
        .environmentObject(environment.csv)
        .environmentObject(environment.activity)
        .environmentObject(environment.locations)
}
