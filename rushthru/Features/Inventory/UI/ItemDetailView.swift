import SwiftUI

struct ItemDetailView: View {
    @EnvironmentObject private var inventory: InventoryService
    private let itemID: UUID

    @State private var latestItem: InventoryItem
    @State private var name: String
    @State private var subName: String
    @State private var type: InventoryItem.ItemType
    @State private var sizeML: Int
    @State private var quantity: Int
    @State private var minimum: Int

    init(item: InventoryItem) {
        self.itemID = item.id
        _latestItem = State(initialValue: item)
        _name = State(initialValue: item.name)
        _subName = State(initialValue: item.subName)
        _type = State(initialValue: item.type)
        _sizeML = State(initialValue: item.sizeML)
        _quantity = State(initialValue: item.quantity)
        _minimum = State(initialValue: item.minimum)
    }

    var body: some View {
        Form {
            Section("Details") {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.words)
                TextField("Variant / Sub-label", text: $subName)
                    .textInputAutocapitalization(.words)
                Picker("Type", selection: $type) {
                    ForEach(InventoryItem.ItemType.allCases, id: \.self) { itemType in
                        Text(itemType.displayName).tag(itemType)
                    }
                }
                Stepper(value: $sizeML, in: 50...10000, step: 10) {
                    Text("Bottle size: \(sizeML) mL")
                }
            }

            Section("Inventory") {
                Stepper("Quantity: \(quantity)", value: $quantity, in: 0...5000)
                Stepper("Minimum: \(minimum)", value: $minimum, in: 0...1000)
            }

            Section {
                Button("Save Changes", action: save)
                    .disabled(!canSave)
            }
        }
        .navigationTitle("Item")
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button(action: increment) {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add one to quantity")
                Button(action: decrement) {
                    Image(systemName: "minus")
                }
                .accessibilityLabel("Remove one from quantity")
            }
        }
        .onReceive(inventory.$items) { _ in
            guard let updated = inventory.item(id: itemID) else { return }
            let hadLocalChanges = isDirty(comparedTo: latestItem)
            latestItem = updated
            if !hadLocalChanges {
                apply(updated)
            }
        }
    }

    private var canSave: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }
        return isDirty(comparedTo: latestItem)
    }

    private func apply(_ item: InventoryItem) {
        name = item.name
        subName = item.subName
        type = item.type
        sizeML = item.sizeML
        quantity = item.quantity
        minimum = item.minimum
    }

    private func isDirty(comparedTo item: InventoryItem) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSub = subName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName != item.name ||
            trimmedSub != item.subName ||
            type != item.type ||
            sizeML != item.sizeML ||
            quantity != item.quantity ||
            minimum != item.minimum
    }

    private func save() {
        var updated = latestItem
        updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.subName = subName.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.type = type
        updated.sizeML = sizeML
        updated.quantity = quantity
        updated.minimum = minimum
        Task {
            await inventory.update(item: updated)
            latestItem = updated
            apply(updated)
        }
    }

    private func increment() {
        quantity += 1
        Task {
            await inventory.incrementQuantity(itemID: itemID, delta: 1)
            if let updated = inventory.item(id: itemID) {
                latestItem = updated
                apply(updated)
            }
        }
    }

    private func decrement() {
        quantity = max(0, quantity - 1)
        Task {
            await inventory.incrementQuantity(itemID: itemID, delta: -1)
            if let updated = inventory.item(id: itemID) {
                latestItem = updated
                apply(updated)
            }
        }
    }
}

#Preview {
    let environment = AppEnvironment(preview: true)
    return ItemDetailView(item: environment.inventory.items.first ?? InventoryItem(name: "Sample", type: .whiskey, sizeML: 750, quantity: 4))
        .environmentObject(environment.inventory)
}
