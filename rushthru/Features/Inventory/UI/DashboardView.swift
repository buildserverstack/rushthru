import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var inventory: InventoryService
    @EnvironmentObject private var refill: RefillService
    @EnvironmentObject private var activity: ActivityLogCoordinator
    @EnvironmentObject private var locations: LocationCoordinator
    @State private var newTypeName: String = ""
    @State private var typeStatus: String = ""
    @State private var newSizeValue: String = ""
    @State private var sizeStatus: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                    summaryCard
                    typeManagementCard
                    sizeManagementCard
                    refillCard
                    bulkCountCard
                    activityCard
                }
                .padding()
                .animation(DesignTokens.Motion.spring(), value: inventory.customTypeOptions)
                .animation(DesignTokens.Motion.spring(), value: inventory.customSizeOptions)
            }
            .navigationTitle("Dashboard")
        }
    }

    private var summaryCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                HStack(alignment: .center) {
                    Text("Inventory Overview")
                        .font(DesignTokens.Typography.subtitle)
                    if refill.refillItems.isEmpty {
                        PillBadge(text: "Healthy", style: .success)
                    } else {
                        PillBadge(text: "Needs attention", style: .warning)
                    }
                }
                if let storeName = locations.storeName(for: inventory.selectedStoreID) {
                    Text("Store: \(storeName)")
                        .font(DesignTokens.Typography.footnote)
                        .foregroundStyle(.secondary)
                } else if inventory.selectedStoreID == nil {
                    Text("Store: All Stores")
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
        }
    }

    private var sizeManagementCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                Text("Size Filters")
                    .font(DesignTokens.Typography.subtitle)
                Text("Add a bottle size to surface it in capture and search drop-downs.")
                    .font(DesignTokens.Typography.footnote)
                    .foregroundStyle(.secondary)
                TextField("New size (e.g. 1500 or 1500ml)", text: $newSizeValue)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                Button("Add Size") {
                    addSize()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(newSizeValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if !inventory.customSizeOptions.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                        Text("Custom Sizes")
                            .font(DesignTokens.Typography.label)
                            .foregroundStyle(.secondary)
                        ForEach(inventory.customSizeOptions, id: \.self) { size in
                            HStack {
                                Text("\(size) mL")
                                Spacer()
                                Button(role: .destructive) {
                                    removeSize(size)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(.vertical, 4)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                }
                if !sizeStatus.isEmpty {
                    Text(sizeStatus)
                        .font(DesignTokens.Typography.footnote)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
            }
        }
    }

    private var typeManagementCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                Text("Type Filters")
                    .font(DesignTokens.Typography.subtitle)
                Text("Add a custom type to reuse across capture, search, and counts.")
                    .font(DesignTokens.Typography.footnote)
                    .foregroundStyle(.secondary)
                TextField("New type name", text: $newTypeName)
                    .textInputAutocapitalization(.words)
                    .textFieldStyle(.roundedBorder)
                Button("Add Type") {
                    addType()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(newTypeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if !inventory.customTypeOptions.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                        Text("Custom Types")
                            .font(DesignTokens.Typography.label)
                            .foregroundStyle(.secondary)
                        ForEach(inventory.customTypeOptions, id: \.self) { type in
                            HStack {
                                Text(type)
                                Spacer()
                                Button(role: .destructive) {
                                    removeType(type)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(.vertical, 4)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                }
                if !typeStatus.isEmpty {
                    Text(typeStatus)
                        .font(DesignTokens.Typography.footnote)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
            }
        }
    }

    private var refillCard: some View {
        SurfaceCard {
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
                        Image(systemName: "arrow.uturn.down")
                            .foregroundColor(DesignTokens.Colors.primary)
                    }
                    .padding(.vertical, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    Divider()
                }
                if refill.refillItems.isEmpty {
                    Text("All items meet minimum stock levels.")
                        .font(DesignTokens.Typography.footnote)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
            }
        }
    }

    private var activityCard: some View {
        SurfaceCard {
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
        }
    }

    private var bulkCountCard: some View {
        SurfaceCard {
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
        }
    }

    private func addType() {
        let trimmed = newTypeName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let added = inventory.addCustomType(trimmed)
        typeStatus = added ? "Added \(trimmed)" : "Type already exists"
        if added {
            HapticsManager.shared.playSuccess()
        } else {
            HapticsManager.shared.playWarning()
        }
        newTypeName = ""
        animateStatusClear(&typeStatus)
    }

    private func addSize() {
        let trimmed = newSizeValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.filter { $0.isNumber }
        guard let value = Int(digits), value > 0 else {
            sizeStatus = "Enter a valid size in milliliters."
            HapticsManager.shared.playWarning()
            return
        }
        let added = inventory.addCustomSize(value)
        sizeStatus = added ? "Added \(value) mL" : "Size already exists"
        if added {
            HapticsManager.shared.playSuccess()
        } else {
            HapticsManager.shared.playWarning()
        }
        newSizeValue = ""
        animateStatusClear(&sizeStatus)
    }

    private func removeType(_ type: String) {
        let outcome = inventory.removeCustomType(type)
        typeStatus = outcome.removed ? "Removed type \(type)" : (outcome.message ?? "Unable to remove type")
        if outcome.removed {
            HapticsManager.shared.playWarning()
        }
        animateStatusClear(&typeStatus)
    }

    private func removeSize(_ size: Int) {
        let outcome = inventory.removeCustomSize(size)
        sizeStatus = outcome.removed ? "Removed size \(size) mL" : (outcome.message ?? "Unable to remove size")
        if outcome.removed {
            HapticsManager.shared.playWarning()
        }
        animateStatusClear(&sizeStatus)
    }

    private func animateStatusClear(_ status: inout String) {
        let currentMessage = status
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if status == currentMessage {
                withAnimation(.easeInOut(duration: DesignTokens.Motion.standard)) {
                    status = ""
                }
            }
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
