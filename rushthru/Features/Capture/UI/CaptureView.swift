import SwiftUI

struct CaptureView: View {
    @EnvironmentObject private var capture: CaptureCoordinator
    @EnvironmentObject private var inventory: InventoryService
    @State private var name: String = ""
    @State private var subName: String = ""
    @State private var type: InventoryItem.ItemType = .whiskey
    @State private var size: String = "750"
    @State private var quantity: Int = 1
    @State private var minimum: Int = 0
    @State private var showConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
            Section("Item Details") {
                TextField("Name", text: $name)
                TextField("Sub-name", text: $subName)
                Picker("Type", selection: $type) {
                    ForEach(InventoryItem.ItemType.allCases, id: \.self) { itemType in
                        Text(itemType.displayName).tag(itemType)
                    }
                }
                TextField("Size (mL)", text: $size)
                    .keyboardType(.numberPad)
                Stepper("Quantity: \(quantity)", value: $quantity, in: 0...500)
                Stepper("Minimum: \(minimum)", value: $minimum, in: 0...200)
            }

            Section {
                Button(action: save) {
                    Label("Save Item", systemImage: "tray.and.arrow.down")
                }
                .disabled(name.isEmpty || size.isEmpty)
            }

            Section("Recent Captures") {
                ForEach(inventory.items.suffix(5)) { item in
                    VStack(alignment: .leading) {
                        Text(item.displayName)
                            .font(.headline)
                        Text("Qty: \(item.quantity)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            }
            .navigationTitle("Capture")
            .alert("Saved", isPresented: $showConfirmation, actions: {}) {
                Text("Item captured successfully")
            }
        }
    }

    private func save() {
        guard let sizeValue = Int(size) else { return }
        let normalized = NormalizedFields(name: name, subName: subName, type: type, sizeML: sizeValue, minimum: minimum, initialQuantity: quantity)
        Task {
            await capture.process(fields: normalized)
            await MainActor.run {
                showConfirmation = true
                name = ""
                subName = ""
                size = "750"
                quantity = 1
                minimum = 0
            }
        }
    }
}

#Preview {
    let environment = AppEnvironment(preview: true)
    CaptureView()
        .environmentObject(environment.capture)
        .environmentObject(environment.inventory)
}
