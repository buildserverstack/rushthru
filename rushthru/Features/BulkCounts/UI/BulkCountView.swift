import SwiftUI

struct BulkCountView: View {
    @EnvironmentObject private var bulkCounts: BulkCountCoordinator
    @EnvironmentObject private var inventory: InventoryService

    var body: some View {
        Form {
            Section("Inventory") {
                ForEach(inventory.items) { item in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(item.displayName)
                                .font(.headline)
                            Text("Current: \(item.quantity)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
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
}

#Preview {
    let environment = AppEnvironment(preview: true)
    BulkCountView()
        .environmentObject(environment.bulkCounts)
        .environmentObject(environment.inventory)
}
