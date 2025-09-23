import SwiftUI

struct BulkCountView: View {
    @EnvironmentObject private var bulkCounts: BulkCountCoordinator
    @EnvironmentObject private var inventory: InventoryService
    @EnvironmentObject private var locations: LocationCoordinator
    @State private var searchText: String = ""
    @State private var selectedType: String? = nil

    var body: some View {
        Form {
            Section("Filter") {
                TextField("Search by name or variant", text: $searchText)
                Picker("Type", selection: $selectedType) {
                    Text("All Types").tag(String?.none)
                    ForEach(inventory.availableTypes, id: \.self) { type in
                        Text(type).tag(Optional(type))
                    }
                }
            }
            Section("Inventory") {
                ForEach(filteredItems) { item in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(item.displayName)
                                .font(.headline)
                            Text("Current: \(item.quantity)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            if let storeName = locations.storeName(for: item.storeID) {
                                Text(storeName)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Stepper(value: Binding(get: {
                            bulkCounts.adjustments.first(where: { $0.item.id == item.id })?.adjustment ?? 0
                        }, set: { newValue in
                            let delta = newValue - (bulkCounts.adjustments.first(where: { $0.item.id == item.id })?.adjustment ?? 0)
                            bulkCounts.addAdjustment(for: item, adjustment: delta)
                        }), in: -100...100) {
                            Text("Δ \(bulkCounts.adjustments.first(where: { $0.item.id == item.id })?.adjustment ?? 0)")
                                .frame(width: 60)
                        }
                    }
                }
            }

            if !bulkCounts.adjustments.isEmpty {
                Section("Pending") {
                    ForEach(bulkCounts.adjustments) { adjustment in
                        Text("\(adjustment.item.displayName): \(adjustment.adjustment >= 0 ? "+" : "")\(adjustment.adjustment)")
                            .font(.footnote)
                    }
                    Button("Commit Adjustments", action: commit)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("Bulk Counts")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Reset", action: bulkCounts.reset)
                    .disabled(bulkCounts.adjustments.isEmpty)
            }
        }
    }

    private func commit() {
        Task { await bulkCounts.commit() }
    }

    private var filteredItems: [InventoryItem] {
        let tokens = searchText.lowercased().split(separator: " ")
        var items = inventory.items
        if let type = selectedType, !type.isEmpty {
            let normalized = ItemIdentity.normalizeType(type)
            items = items.filter { ItemIdentity.normalizeType($0.type) == normalized }
        }
        if !tokens.isEmpty {
            items = items.filter { item in
                let haystack = "\(item.name.lowercased()) \(item.subName.lowercased())"
                return tokens.allSatisfy { haystack.contains($0) }
            }
        }
        return items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

#Preview {
    let environment = AppEnvironment(preview: true)
    BulkCountView()
        .environmentObject(environment.bulkCounts)
        .environmentObject(environment.inventory)
        .environmentObject(environment.locations)
}
