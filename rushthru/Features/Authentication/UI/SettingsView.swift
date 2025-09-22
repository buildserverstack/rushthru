import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var csv: CSVCoordinator
    @EnvironmentObject private var activity: ActivityLogCoordinator
    @EnvironmentObject private var locations: LocationCoordinator
    @State private var pin: String = ""
    @State private var confirmPIN: String = ""
    @State private var exportText: String = ""
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var newStoreName: String = ""
    @State private var storeStatus: String = ""

    var body: some View {
        NavigationStack {
            Form {
                if !locations.stores.isEmpty {
                    Section("Store Filter") {
                    Picker("Active Store", selection: Binding(
                        get: { locations.selectedStoreID ?? locations.stores.first?.id },
                        set: { locations.selectedStoreID = $0 }
                    )) {
                        ForEach(locations.stores) { store in
                            Text(store.name)
                                .tag(Optional(store.id))
                        }
                    }
                    TextField("New store name", text: $newStoreName)
                    Button("Add Store") {
                        let trimmed = newStoreName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        Task {
                            let added = await locations.createStore(named: trimmed)
                            await MainActor.run {
                                storeStatus = added ? "Added \(trimmed)" : "Store already exists"
                                if added { newStoreName = "" }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    storeStatus = ""
                                }
                            }
                        }
                    }
                    .disabled(newStoreName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if !storeStatus.isEmpty {
                        Text(storeStatus)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

                Section("Security") {
                    SecureField("New PIN", text: $pin)
                    SecureField("Confirm PIN", text: $confirmPIN)
                    Button("Update PIN", action: updatePIN)
                        .disabled(pin.count < 4 || pin != confirmPIN)
                    Toggle("Enable Biometrics", isOn: $auth.biometricsEnabled)
                    Stepper("Auto-lock after \(auth.autoLockMinutes) minutes", value: $auth.autoLockMinutes, in: 1...30)
                }

                Section("CSV Backup") {
                    Button("Export Inventory") {
                        exportText = csv.exportInventory()
                    }
                    if !exportText.isEmpty {
                        ShareLink(item: exportText)
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
            .alert("Error", isPresented: $showErrorAlert, actions: {}) {
                Text(errorMessage)
            }
        }
    }

    private func updatePIN() {
        guard pin == confirmPIN else {
            errorMessage = "PINs do not match"
            showErrorAlert = true
            return
        }
        auth.setPIN(pin)
        pin = ""
        confirmPIN = ""
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
