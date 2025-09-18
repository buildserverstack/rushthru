import SwiftUI

struct ItemDetailView: View {
    @EnvironmentObject private var inventory: InventoryService
    let item: InventoryItem
    @State private var quantity: Int
    @State private var minimum: Int

    init(item: InventoryItem) {
        self.item = item
        _quantity = State(initialValue: item.quantity)
        _minimum = State(initialValue: item.minimum)
    }

    var body: some View {
        Form {
            Section("Details") {
                Text(item.displayName)
                Text("Type: \(item.type.displayName)")
                Text("Size: \(item.sizeML) mL")
            }

            Section("Inventory") {
                Stepper("Quantity: \(quantity)", value: $quantity, in: 0...1000)
                Stepper("Minimum: \(minimum)", value: $minimum, in: 0...300)
            }

            Section {
                Button("Save Changes", action: save)
            }
        }
        .navigationTitle("Item")
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button(action: increment) {
                    Image(systemName: "plus")
                }
                Button(action: decrement) {
                    Image(systemName: "minus")
                }
            }
        }
    }

    private func save() {
        var updated = item
        updated.quantity = quantity
        updated.minimum = minimum
        Task { await inventory.update(item: updated) }
    }

    private func increment() {
        Task { await inventory.incrementQuantity(itemID: item.id, delta: 1) }
    }

    private func decrement() {
        Task { await inventory.incrementQuantity(itemID: item.id, delta: -1) }
    }
}

#Preview {
    let environment = AppEnvironment(preview: true)
    return ItemDetailView(item: environment.inventory.items.first ?? InventoryItem(name: "Sample", type: .whiskey, sizeML: 750, quantity: 4))
        .environmentObject(environment.inventory)
}
