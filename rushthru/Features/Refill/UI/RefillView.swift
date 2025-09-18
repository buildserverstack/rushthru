import SwiftUI

struct RefillView: View {
    @EnvironmentObject private var refill: RefillService
    @EnvironmentObject private var inventory: InventoryService
    @State private var selectedItem: InventoryItem?
    @State private var quantityMoved: Int = 1
    @State private var hapticTriggered = false

    var body: some View {
        NavigationStack {
            List {
            Section("Items below minimum") {
                ForEach(refill.refillItems) { item in
                    VStack(alignment: .leading) {
                        Text(item.displayName)
                            .font(.headline)
                        Text("Current: \(item.quantity) / Minimum: \(item.minimum)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .onTapGesture {
                        selectedItem = item
                        quantityMoved = 1
                    }
                }
            }
            if refill.refillItems.isEmpty {
                Text("Great! Everything is stocked.")
                    .foregroundStyle(.secondary)
            }
            }
            .sheet(item: $selectedItem) { item in
                NavigationStack {
                    Form {
                        Stepper("Moved to shelf: \(quantityMoved)", value: $quantityMoved, in: 1...max(1, item.quantity))
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
                            .disabled(item.quantity == 0)
                        }
                    }
                }
            }
            .navigationTitle("Refill List")
        }
    }
}

#Preview {
    let environment = AppEnvironment(preview: true)
    RefillView()
        .environmentObject(environment.refill)
        .environmentObject(environment.inventory)
}
