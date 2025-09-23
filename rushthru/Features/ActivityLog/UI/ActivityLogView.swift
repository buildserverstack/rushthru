import SwiftUI

struct ActivityLogView: View {
    @EnvironmentObject private var activity: ActivityLogCoordinator

    var body: some View {
        List(activity.entries) { entry in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(entry.action.rawValue.capitalized)
                        .font(DesignTokens.Typography.body.weight(.semibold))
                    Spacer()
                    Text(entry.createdAt, style: .time)
                        .font(DesignTokens.Typography.footnote)
                        .foregroundStyle(.secondary)
                }
                if let metadata = entry.metadataJSON, !metadata.isEmpty {
                    Text(metadata)
                        .font(DesignTokens.Typography.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 8)
        }
        .navigationTitle("Activity Log")
    }
}

#Preview {
    let environment = AppEnvironment(preview: true)
    ActivityLogView().environmentObject(environment.activity)
}
