import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var csv: CSVViewModel
    @EnvironmentObject private var activity: ActivityLogViewModel
    @EnvironmentObject private var locations: LocationsViewModel
    @EnvironmentObject private var inventory: InventoryService
    @EnvironmentObject private var refill: RefillViewModel
    @EnvironmentObject private var search: SearchViewModel
    @EnvironmentObject private var capture: CaptureViewModel
    @EnvironmentObject private var bulkCounts: BulkCountViewModel
    @State private var exportText: String = ""
    @State private var newStoreName: String = ""
    @State private var storeStatus: String = ""
    @State private var importText: String = ""
    @State private var importStatus: String = ""
    @State private var dataStatus: String = ""
    @State private var showClearAllAlert = false
    @State private var showRemovePINAlert = false
    @State private var newPIN: String = ""
    @State private var confirmPIN: String = ""
    @State private var pinStatus: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Security") {
                    if auth.hasPIN {
                        Label("Store PIN enabled", systemImage: "lock.fill")
                            .foregroundStyle(.secondary)
                    } else {
                        Label("Store PIN not set", systemImage: "lock.open")
                            .foregroundStyle(.secondary)
                    }

                    SecureField("New PIN", text: $newPIN)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .onChange(of: newPIN) { _, value in
                            sanitizePIN(&newPIN, from: value)
                        }

                    SecureField("Confirm PIN", text: $confirmPIN)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .onChange(of: confirmPIN) { _, value in
                            sanitizePIN(&confirmPIN, from: value)
                        }

                    Button("Save PIN") {
                        setPIN()
                    }
                    .disabled(!canSavePIN)

                    if auth.hasPIN {
                        Button("Lock Now") {
                            auth.lock()
                            pinStatus = "App locked. Enter the new PIN to continue."
                            clearPinStatus(after: 3)
                        }

                        Button("Remove PIN", role: .destructive) {
                            showRemovePINAlert = true
                        }
                    }

                    if !pinStatus.isEmpty {
                        Text(pinStatus)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

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
                    if locations.selectedStoreID != nil, !locations.stores.isEmpty {
                        Button("Show All Stores") {
                            locations.selectedStoreID = nil
                            storeStatus = "Showing all stores"
                            clearStoreStatus(after: 2)
                        }
                    }
                    if locations.stores.isEmpty {
                        Text("No stores yet. Add one to start tracking inventory.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if !storeStatus.isEmpty {
                        Text(storeStatus)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
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

                Section("Data Management") {
                    Button(role: .destructive) {
                        showClearAllAlert = true
                    } label: {
                        Label("Clear All Data", systemImage: "trash")
                    }
                    if !dataStatus.isEmpty {
                        Text(dataStatus)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .alert("Erase all data?", isPresented: $showClearAllAlert) {
                Button("Delete Everything", role: .destructive) {
                    clearAllData()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This removes all inventory, locations, refill tasks, activity logs, and history. This action cannot be undone.")
            }
            .alert("Remove PIN?", isPresented: $showRemovePINAlert) {
                Button("Remove PIN", role: .destructive) {
                    removePIN()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Disabling the PIN lets anyone with the device open ShelfTrack.")
            }
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

    private func clearDataStatus(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            dataStatus = ""
        }
    }

    @MainActor
    private func clearAllData() {
        capture.resetDraft()
        bulkCounts.reset()
        refill.clearAll()
        inventory.clearAll()
        locations.clearAll()
        search.clearAll()
        csv.resetState()
        activity.clearAll()
        auth.clearPIN()
        newPIN = ""
        confirmPIN = ""
        pinStatus = ""
        exportText = ""
        importText = ""
        importStatus = ""
        storeStatus = ""
        dataStatus = "All app data has been cleared."
        clearDataStatus(after: 3)
    }

    private var canSavePIN: Bool {
        newPIN.count >= 4 && newPIN == confirmPIN
    }

    private func sanitizePIN(_ target: inout String, from value: String) {
        let filtered = value.filter { $0.isNumber }
        if filtered.count > 6 {
            target = String(filtered.prefix(6))
        } else {
            target = String(filtered)
        }
    }

    private func setPIN() {
        guard canSavePIN else { return }
        auth.setPIN(newPIN)
        pinStatus = "PIN saved. The app is now locked."
        newPIN = ""
        confirmPIN = ""
        clearPinStatus(after: 3)
    }

    private func removePIN() {
        auth.clearPIN()
        pinStatus = "PIN removed."
        newPIN = ""
        confirmPIN = ""
        clearPinStatus(after: 3)
    }

    private func clearPinStatus(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            pinStatus = ""
        }
    }
}

#Preview {
    let environment = AppEnvironment(preview: true)
    SettingsView()
        .environmentObject(environment.inventory)
        .environmentObject(environment.auth)
        .environmentObject(environment.csv)
        .environmentObject(environment.activity)
        .environmentObject(environment.locations)
        .environmentObject(environment.refill)
        .environmentObject(environment.search)
        .environmentObject(environment.capture)
        .environmentObject(environment.bulkCounts)
}
