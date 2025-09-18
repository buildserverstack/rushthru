import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var csv: CSVCoordinator
    @EnvironmentObject private var activity: ActivityLogCoordinator
    @State private var pin: String = ""
    @State private var confirmPIN: String = ""
    @State private var exportText: String = ""
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            Form {
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
}
