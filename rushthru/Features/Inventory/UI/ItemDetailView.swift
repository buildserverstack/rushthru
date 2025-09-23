import SwiftUI

struct ItemDetailView: View {
    @EnvironmentObject private var inventory: InventoryService
    @EnvironmentObject private var locations: LocationCoordinator
    private let itemID: UUID

    @State private var latestItem: InventoryItem
    @State private var name: String
    @State private var subName: String
    @State private var type: String
    @State private var sizeML: Int
    @State private var quantity: Int
    @State private var minimum: Int
    @State private var aisle: String
    @State private var shelf: String
    @State private var row: String
    @State private var column: String

    init(item: InventoryItem) {
        self.itemID = item.id
        _latestItem = State(initialValue: item)
        _name = State(initialValue: item.name)
        _subName = State(initialValue: item.subName)
        _type = State(initialValue: item.type)
        _sizeML = State(initialValue: item.sizeML)
        _quantity = State(initialValue: item.quantity)
        _minimum = State(initialValue: item.minimum)
        _aisle = State(initialValue: item.aisle)
        _shelf = State(initialValue: item.shelf)
        _row = State(initialValue: item.row)
        _column = State(initialValue: item.column)
    }

    var body: some View {
        Form {
            Section("Details") {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.words)
                TextField("Variant / Sub-label", text: $subName)
                    .textInputAutocapitalization(.words)
                Picker("Type", selection: $type) {
                    ForEach(inventory.availableTypes, id: \.self) { itemType in
                        Text(itemType).tag(itemType)
                    }
                }
                Stepper(value: $sizeML, in: 50...10000, step: 10) {
                    Text("Bottle size: \(sizeML) mL")
                }
                if let storeName = locations.storeName(for: latestItem.storeID) {
                    Label(storeName, systemImage: "building.2")
                        .labelStyle(.titleAndIcon)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Location") {
                Picker("Aisle", selection: $aisle) {
                    Text("None").tag("")
                    ForEach(locations.aisleOptions, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .pickerStyle(.menu)
                Picker("Shelf", selection: $shelf) {
                    Text("None").tag("")
                    ForEach(locations.shelfOptions, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .pickerStyle(.menu)
                Picker("Row", selection: $row) {
                    Text("None").tag("")
                    ForEach(locations.rowOptions, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .pickerStyle(.menu)
                Picker("Column", selection: $column) {
                    Text("None").tag("")
                    ForEach(locations.columnOptions, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .pickerStyle(.menu)
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
        aisle = item.aisle
        shelf = item.shelf
        row = item.row
        column = item.column
    }

    private func isDirty(comparedTo item: InventoryItem) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSub = subName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName != item.name ||
            trimmedSub != item.subName ||
            type != item.type ||
            sizeML != item.sizeML ||
            quantity != item.quantity ||
            minimum != item.minimum ||
            aisle != item.aisle ||
            shelf != item.shelf ||
            row != item.row ||
            column != item.column
    }

    private func save() {
        var updated = latestItem
        updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.subName = subName.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.type = type
        updated.sizeML = sizeML
        updated.quantity = quantity
        updated.minimum = minimum
        updated.aisle = aisle
        updated.shelf = shelf
        updated.row = row
        updated.column = column
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
    let fallbackStore = environment.locations.selectedStoreID ?? environment.locations.stores.first?.id ?? UUID()
    let sample = InventoryItem(name: "Sample", type: "Whiskey", sizeML: 750, quantity: 4, storeID: fallbackStore)
    return ItemDetailView(item: environment.inventory.items.first ?? sample)
        .environmentObject(environment.inventory)
        .environmentObject(environment.locations)
}
