import SwiftUI

struct RefillView: View {
    @EnvironmentObject private var refill: RefillService
    @State private var selectedItem: InventoryItem?
    @State private var quantityMoved: Int = 1
    @State private var showAddManual = false
    @State private var manualName: String = ""
    @State private var manualQuantity: Int = 1

    var body: some View {
        NavigationStack {
            List {
                Section("Items below minimum") {
                    if refill.refillItems.isEmpty {
                        Text("Great! Everything is stocked.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(refill.refillItems) { item in
                            Button {
                                selectedItem = item
                                quantityMoved = max(1, item.minimum - item.quantity)
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(item.displayName)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text("Current: \(item.quantity) / Minimum: \(item.minimum)")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }

                Section("Manual refill items") {
                    if refill.manualTasks.isEmpty {
                        Text("Add items you plan to restock and strike them when done.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(refill.manualTasks) { task in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(task.name)
                                        .font(.headline)
                                    Text("Requested: \(task.quantity)")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                    Text("Available: \(task.availableQuantity)")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Strike") {
                                    refill.strikeManual(taskID: task.id)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        .onDelete { indexSet in
                            refill.removeManualTasks(at: indexSet)
                        }
                    }
                }
            }
            .sheet(item: $selectedItem) { item in
                NavigationStack {
                    Form {
                        Stepper("Moved to shelf: \(quantityMoved)", value: $quantityMoved, in: 1...200)
                    }
                    .navigationTitle(item.displayName)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { selectedItem = nil }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Strike") {
                                Task {
                                    await refill.strike(itemID: item.id, movedQuantity: quantityMoved)
                                    selectedItem = nil
                                }
                            }
                            .disabled(quantityMoved <= 0)
                        }
                    }
                }
            }
            .sheet(isPresented: $showAddManual) {
                NavigationStack {
                    Form {
                        TextField("Item name", text: $manualName)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.words)
                        let suggestions = refill.suggestions(for: manualName)
                        if !suggestions.isEmpty {
                            Section("Suggestions") {
                                ForEach(suggestions) { suggestion in
                                    Button {
                                        manualName = suggestion.displayName
                                        let defaultQuantity = suggestion.minimum - suggestion.quantity
                                        manualQuantity = max(1, min(500, defaultQuantity))
                                    } label: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(suggestion.displayName)
                                                .font(.body)
                                                .foregroundStyle(.primary)
                                            Text("On hand: \(suggestion.quantity)  •  Min: \(suggestion.minimum)")
                                                .font(.footnote)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                        Stepper("Quantity needed: \(manualQuantity)", value: $manualQuantity, in: 1...500)
                    }
                    .navigationTitle("Add refill item")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                showAddManual = false
                                resetManualForm()
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Add") {
                                refill.addManualTask(name: manualName, quantity: manualQuantity)
                                showAddManual = false
                                resetManualForm()
                            }
                            .disabled(manualName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
            }
            .navigationTitle("Refill List")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddManual = true
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
        }
    }

    private func resetManualForm() {
        manualName = ""
        manualQuantity = 1
    }
}

#Preview {
    let environment = AppEnvironment(preview: true)
    RefillView()
        .environmentObject(environment.refill)
}
