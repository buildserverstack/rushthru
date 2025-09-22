import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var inventory: InventoryService
    @EnvironmentObject private var refill: RefillService
    @EnvironmentObject private var activity: ActivityLogCoordinator
    @EnvironmentObject private var locations: LocationCoordinator
    @State private var newTypeName: String = ""
    @State private var typeStatus: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                    summaryCard
                    typeManagementCard
                    refillCard
                    bulkCountCard
                    activityCard
                }
                .padding()
            }
            .navigationTitle("Dashboard")
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("Inventory Overview")
                .font(DesignTokens.Typography.subtitle)
            if let storeName = locations.storeName(for: inventory.selectedStoreID) {
                Text("Store: \(storeName)")
                    .font(DesignTokens.Typography.footnote)
                    .foregroundStyle(.secondary)
            }
            HStack {
                VStack(alignment: .leading) {
                    Text("Total Items")
                        .font(DesignTokens.Typography.label)
                        .foregroundStyle(.secondary)
                    Text("\(inventory.items.count)")
                        .font(.title)
                }
                Spacer()
                VStack(alignment: .leading) {
                    Text("Below Minimum")
                        .font(DesignTokens.Typography.label)
                        .foregroundStyle(.secondary)
                    Text("\(refill.refillItems.count)")
                        .font(.title)
                        .foregroundStyle(refill.refillItems.isEmpty ? Color.primary : DesignTokens.Colors.warning)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemBackground)))
    }

    private var typeManagementCard: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("Type Filters")
                .font(DesignTokens.Typography.subtitle)
            Text("Add a custom type to reuse across capture, search, and counts.")
                .font(DesignTokens.Typography.footnote)
                .foregroundStyle(.secondary)
            TextField("New type name", text: $newTypeName)
                .textInputAutocapitalization(.words)
            Button("Add Type") {
                addType()
            }
            .buttonStyle(.borderedProminent)
            .disabled(newTypeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if !typeStatus.isEmpty {
                Text(typeStatus)
                    .font(DesignTokens.Typography.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemBackground)))
    }

    private var refillCard: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack {
                Text("Refill List")
                    .font(DesignTokens.Typography.subtitle)
                Spacer()
                NavigationLink("View All") {
                    RefillView()
                }
            }
            ForEach(refill.refillItems.prefix(3)) { item in
                HStack {
                    VStack(alignment: .leading) {
                        Text(item.displayName)
                            .font(DesignTokens.Typography.body.weight(.semibold))
                        Text("Stock: \(item.quantity) / Minimum: \(item.minimum)")
                            .font(DesignTokens.Typography.footnote)
                            .foregroundStyle(.secondary)
                        if let storeName = locations.storeName(for: item.storeID) {
                            Text(storeName)
                                .font(DesignTokens.Typography.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Label("Refill", systemImage: "arrow.uturn.down")
                        .labelStyle(.iconOnly)
                        .foregroundColor(DesignTokens.Colors.primary)
                }
                .padding(.vertical, 8)
                Divider()
            }
            if refill.refillItems.isEmpty {
                Text("All items meet minimum stock levels.")
                    .font(DesignTokens.Typography.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemBackground)))
    }

    private var activityCard: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack {
                Text("Recent Activity")
                    .font(DesignTokens.Typography.subtitle)
                Spacer()
                NavigationLink("Log") {
                    ActivityLogView()
                }
            }
            ForEach(activity.entries.prefix(5)) { entry in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.action.rawValue.capitalized)
                            .font(DesignTokens.Typography.body.weight(.semibold))
                        Text(entry.createdAt, style: .time)
                            .font(DesignTokens.Typography.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
                Divider()
            }
            if activity.entries.isEmpty {
                Text("No activity yet.")
                    .font(DesignTokens.Typography.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemBackground)))
    }

    private var bulkCountCard: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("Bulk Counts")
                .font(DesignTokens.Typography.subtitle)
            NavigationLink {
                BulkCountView()
            } label: {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Run a bulk count session")
                            .font(DesignTokens.Typography.body)
                        Text("Capture aisle-wide adjustments with one commit.")
                            .font(DesignTokens.Typography.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemBackground)))
    }

    private func addType() {
        let trimmed = newTypeName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let added = inventory.addCustomType(trimmed)
        typeStatus = added ? "Added \(trimmed)" : "Type already exists"
        newTypeName = ""
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            typeStatus = ""
        }
    }
}

#Preview {
    let environment = AppEnvironment(preview: true)
    return DashboardView()
        .environmentObject(environment.inventory)
        .environmentObject(environment.refill)
        .environmentObject(environment.activity)
        .environmentObject(environment.locations)
}
