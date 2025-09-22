import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var search: SearchCoordinator
    @EnvironmentObject private var inventory: InventoryService
    @EnvironmentObject private var locations: LocationCoordinator

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Search inventory", text: $search.query)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { search.addToHistory(search.query) }
                    Picker("Filter", selection: $search.selectedType) {
                        Text("All Types").tag(String?.none)
                        ForEach(inventory.availableTypes, id: \.self) { type in
                            Text(type).tag(Optional(type))
                        }
                    }
                    .pickerStyle(.menu)
                    Picker("Size", selection: $search.selectedSize) {
                        Text("All Sizes").tag(Int?.none)
                        ForEach(inventory.availableSizes.sorted(), id: \.self) { size in
                            Text("\(size) mL").tag(Optional(size))
                        }
                    }
                    .pickerStyle(.menu)
                }

                if search.query.isEmpty {
                    Section("Recent Searches") {
                        if search.history.isEmpty {
                            Text("Start typing to search items")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(search.history) { entry in
                                Button(entry.query) {
                                    search.selectSuggestion(entry.query)
                                }
                            }
                        }
                    }
                }

                Section("Results") {
                    ForEach(search.results) { item in
                        NavigationLink(destination: ItemDetailView(item: item)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.displayName)
                                    .font(.headline)
                                Text("Qty: \(item.quantity) — Minimum \(item.minimum)")
                                    .font(.footnote)
                                    .foregroundStyle(item.isBelowMinimum ? DesignTokens.Colors.warning : .secondary)
                                if let storeName = locations.storeName(for: item.storeID) {
                                    Text(storeName)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                if !item.locationDescription.isEmpty {
                                    Text(item.locationDescription)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if search.results.isEmpty {
                        Text("No items found")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Search")
        }
    }
}

#Preview {
    let environment = AppEnvironment(preview: true)
    SearchView()
        .environmentObject(environment.search)
        .environmentObject(environment.inventory)
        .environmentObject(environment.locations)
}
