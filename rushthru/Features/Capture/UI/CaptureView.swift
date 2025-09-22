import SwiftUI

struct CaptureView: View {
    @EnvironmentObject private var capture: CaptureCoordinator
    @EnvironmentObject private var inventory: InventoryService
    @EnvironmentObject private var locations: LocationCoordinator
    @State private var editableFields = EditableFields()
    @State private var showConfirmation = false
    @State private var confirmationMessage = ""
    @State private var showDuplicatePrompt = false
    @State private var duplicateContext: CaptureCoordinator.PendingDuplicate?
    #if canImport(UIKit)
    @State private var activeImageSource: ImagePickerSource?
    #endif

    var body: some View {
        NavigationStack {
            List {
                scanSection
                detailsSection
                saveSection
                recognizedSection
                inventorySection
            }
            .navigationTitle("Capture")
            .onAppear {
                editableFields = EditableFields(from: capture.draftFields)
            }
            .onChange(of: capture.draftFields) { newValue in
                editableFields = EditableFields(from: newValue)
            }
            .onChange(of: capture.pendingDuplicate) { newValue in
                duplicateContext = newValue
                showDuplicatePrompt = newValue != nil
            }
            .alert(confirmationMessage, isPresented: $showConfirmation) {
                Button("OK", role: .cancel) { }
            }
            .alert("Update existing item?", isPresented: $showDuplicatePrompt, presenting: duplicateContext) { context in
                Button("Update Stock") {
                    Task {
                        await capture.acceptDuplicateUpdate()
                        await MainActor.run {
                            confirmationMessage = "Updated stock for \(context.existing.displayName)."
                            showConfirmation = true
                        }
                    }
                }
                Button("Create New Item") {
                    Task {
                        await capture.createDuplicateItem()
                        await MainActor.run {
                            confirmationMessage = "Saved \(context.proposed.name) as a new item."
                            showConfirmation = true
                        }
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: { context in
                Text("“\(context.existing.displayName)” already exists with \(context.existing.quantity) in stock. Update the existing count by \(context.proposed.initialQuantity)?")
            }
            #if canImport(UIKit)
            .sheet(item: $activeImageSource) { source in
                ImagePicker(sourceType: source.sourceType) { data in
                    Task { await capture.process(imageData: data) }
                }
            }
            #endif
        }
    }

    private var scanSection: some View {
        Section("Scan or import") {
            #if canImport(UIKit)
            Button {
                activeImageSource = .camera
            } label: {
                Label("Scan with Camera", systemImage: "camera")
            }
            .disabled(!ImagePickerSource.camera.isAvailable)

            Button {
                activeImageSource = .photoLibrary
            } label: {
                Label("Import from Photos", systemImage: "photo")
            }
            .disabled(!ImagePickerSource.photoLibrary.isAvailable)
            #else
            Text("Camera and photo import are available on device builds.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            #endif

            if capture.isProcessing {
                ProgressView("Scanning…")
            }

            if let error = capture.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private var detailsSection: some View {
        Section("Item details") {
            TextField("Name", text: $editableFields.name)
            TextField("Sub-name", text: $editableFields.subName)
            Picker("Type", selection: $editableFields.type) {
                ForEach(inventory.availableTypes, id: \.self) { itemType in
                    Text(itemType).tag(itemType)
                }
            }
            TextField("Size (mL)", text: $editableFields.size)
                .keyboardType(.numberPad)
            Stepper("Quantity: \(editableFields.quantity)", value: $editableFields.quantity, in: 1...500)
            Stepper("Minimum: \(editableFields.minimum)", value: $editableFields.minimum, in: 0...200)
        }
    }

    private var saveSection: some View {
        Section {
            Button(action: save) {
                Label("Save Item", systemImage: "tray.and.arrow.down")
            }
            .disabled(editableFields.normalizedFields == nil || editableFields.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var recognizedSection: some View {
        Section("Recognized text") {
            if capture.lastResult.fields.isEmpty {
                Text("Scan a label to see suggested fields.")
                    .foregroundStyle(.secondary)
            } else {
                Text("Tap a suggestion to fill a field.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                ForEach(OCRCandidateField.FieldType.allCases, id: \.self) { fieldType in
                    let options = options(for: fieldType)
                    if !options.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(label(for: fieldType))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            ForEach(options, id: \.self) { option in
                                Button {
                                    apply(option)
                                } label: {
                                    HStack {
                                        Text(option.value)
                                            .font(.body)
                                        Spacer()
                                        if isCandidateSelected(option) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.tint)
                                        } else {
                                            Image(systemName: "plus.circle")
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private var inventorySection: some View {
        Section("Inventory") {
            if sortedInventory.isEmpty {
                Text("No items captured yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sortedInventory) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.displayName)
                            .font(.headline)
                        HStack(spacing: 12) {
                            Text("Qty: \(item.quantity)")
                            Text("Minimum: \(item.minimum)")
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        if let storeName = locations.storeName(for: item.storeID) {
                            Text(storeName)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Text("Updated \(item.updatedAt, style: .time)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var sortedInventory: [InventoryItem] {
        inventory.items.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func label(for type: OCRCandidateField.FieldType) -> String {
        switch type {
        case .name:
            return "Name"
        case .subName:
            return "Sub-name"
        case .type:
            return "Type"
        case .sizeML:
            return "Size"
        }
    }

    private func options(for fieldType: OCRCandidateField.FieldType) -> [OCRCandidateField] {
        capture.lastResult.fields
            .filter { $0.type == fieldType }
            .sorted { $0.confidence > $1.confidence }
    }

    private func apply(_ candidate: OCRCandidateField) {
        switch candidate.type {
        case .name:
            editableFields.name = candidate.value.trimmingCharacters(in: .whitespacesAndNewlines)
        case .subName:
            editableFields.subName = candidate.value.trimmingCharacters(in: .whitespacesAndNewlines)
        case .type:
            if let matchedType = normalizedType(from: candidate.value) {
                editableFields.type = matchedType
            }
        case .sizeML:
            if let size = parseSizeValue(from: candidate.value) {
                editableFields.size = String(size)
            }
        }
    }

    private func isCandidateSelected(_ candidate: OCRCandidateField) -> Bool {
        switch candidate.type {
        case .name:
            return compare(candidate.value, editableFields.name)
        case .subName:
            return compare(candidate.value, editableFields.subName)
        case .type:
            guard let matchedType = normalizedType(from: candidate.value) else { return false }
            return editableFields.type == matchedType
        case .sizeML:
            guard let size = parseSizeValue(from: candidate.value), let currentSize = Int(editableFields.size) else { return false }
            return size == currentSize
        }
    }

    private func compare(_ lhs: String, _ rhs: String) -> Bool {
        lhs.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(rhs.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
    }

    private func normalizedType(from value: String) -> String? {
        let normalized = ItemIdentity.normalizeType(value)
        if let match = inventory.matchingType(for: value) {
            return match
        }
        let fallback = inventory.availableTypes.first { ItemIdentity.normalizeType($0) == normalized }
        return fallback
    }

    private func parseSizeValue(from value: String) -> Int? {
        let lowered = value.lowercased()
        let pattern = "(\\d+(?:\\.\\d+)?)\\s*(ml|milliliter|millilitre|l|liter|litre)?"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let range = NSRange(location: 0, length: lowered.utf16.count)
            if let match = regex.firstMatch(in: lowered, options: [], range: range),
               let valueRange = Range(match.range(at: 1), in: lowered) {
                let unitRange = Range(match.range(at: 2), in: lowered)
                let valueString = String(lowered[valueRange])
                if let numeric = Double(valueString) {
                    let unit = unitRange.map { String(lowered[$0]) } ?? "ml"
                    if unit.hasPrefix("l") {
                        return Int((numeric * 1000).rounded())
                    } else {
                        return Int(numeric.rounded())
                    }
                }
            }
        }

        let digits = value.filter { $0.isNumber }
        return Int(digits)
    }

    private func save() {
        guard let normalized = editableFields.normalizedFields else { return }
        Task {
            await capture.process(fields: normalized)
            await MainActor.run {
                if capture.pendingDuplicate == nil {
                    confirmationMessage = "Saved \(normalized.name)."
                    showConfirmation = true
                }
            }
        }
    }
}

private struct EditableFields {
    var name: String = ""
    var subName: String = ""
    var type: String = InventoryItem.defaultTypes.last ?? "Other"
    var size: String = "750"
    var quantity: Int = 1
    var minimum: Int = 0

    init(from normalized: NormalizedFields? = nil) {
        if let normalized {
            name = normalized.name
            subName = normalized.subName
            type = normalized.type
            size = String(normalized.sizeML)
            quantity = max(1, normalized.initialQuantity)
            minimum = normalized.minimum
        }
    }

    var normalizedFields: NormalizedFields? {
        guard let sizeValue = Int(size) else { return nil }
        return NormalizedFields(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            subName: subName.trimmingCharacters(in: .whitespacesAndNewlines),
            type: type,
            sizeML: sizeValue,
            minimum: minimum,
            initialQuantity: quantity
        )
    }
}

#Preview {
    let environment = AppEnvironment(preview: true)
    CaptureView()
        .environmentObject(environment.capture)
        .environmentObject(environment.inventory)
        .environmentObject(environment.locations)
}

#if canImport(UIKit)
import UIKit

private enum ImagePickerSource: Identifiable {
    case camera
    case photoLibrary

    var id: Int { hashValue }

    var sourceType: UIImagePickerController.SourceType {
        switch self {
        case .camera:
            return .camera
        case .photoLibrary:
            return .photoLibrary
        }
    }

    var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(sourceType)
    }

}

private struct ImagePicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let completion: (Data) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let parent: ImagePicker

        init(parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            defer { parent.dismiss() }
            guard let image = info[.originalImage] as? UIImage,
                  let data = image.jpegData(compressionQuality: 0.85) else { return }
            parent.completion(data)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
#endif
