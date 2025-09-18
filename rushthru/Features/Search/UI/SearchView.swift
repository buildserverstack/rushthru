import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var search: SearchCoordinator
    @EnvironmentObject private var inventory: InventoryService

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Search inventory", text: $search.query)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { search.addToHistory(search.query) }
                    Picker("Filter", selection: $search.selectedType) {
                        Text("All Types").tag(InventoryItem.ItemType?.none)
                        ForEach(InventoryItem.ItemType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(Optional(type))
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
}
