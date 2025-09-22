import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var inventory: InventoryService
    @EnvironmentObject private var refill: RefillService
    @EnvironmentObject private var activity: ActivityLogCoordinator

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                    summaryCard
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
}

#Preview {
    let environment = AppEnvironment(preview: true)
    return DashboardView()
        .environmentObject(environment.inventory)
        .environmentObject(environment.refill)
        .environmentObject(environment.activity)
        .environmentObject(environment.locations)
}
