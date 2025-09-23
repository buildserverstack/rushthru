import SwiftUI

struct CaptureView: View {
    @EnvironmentObject private var capture: CaptureViewModel
    @EnvironmentObject private var inventory: InventoryService
    @EnvironmentObject private var locations: LocationsViewModel
    @State private var editableFields = EditableFields()
    @State private var showConfirmation = false
    @State private var confirmationMessage = ""
    @State private var showDuplicatePrompt = false
    @State private var duplicateContext: CaptureViewModel.PendingDuplicate?
    @Namespace private var suggestionNamespace
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
                if newValue != nil {
                    HapticsManager.shared.playWarning()
                }
            }
            .onChange(of: capture.errorMessage) { newValue in
                guard newValue != nil else { return }
                HapticsManager.shared.playError()
            }
            .alert(confirmationMessage, isPresented: $showConfirmation) {
                Button("OK", role: .cancel) { }
            }
            .alert(duplicateContext?.alertTitle ?? "", isPresented: $showDuplicatePrompt, presenting: duplicateContext) { context in
                Button(context.primaryActionTitle) {
                    Task {
                        await capture.acceptDuplicateUpdate()
                        await MainActor.run {
                            confirmationMessage = context.successMessage
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
                Text(context.alertMessage)
            }
            #if canImport(UIKit)
            .sheet(item: $activeImageSource) { source in
                ImagePicker(source: source) { data in
                    Task { await capture.process(imageData: data, from: source.captureSource) }
                }
            }
            #endif
        }
        .listStyle(.insetGrouped)
        .overlay(alignment: .top) {
            if capture.isProcessing {
                ProcessingBanner()
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 8)
            }
        }
        .animation(DesignTokens.Motion.spring(), value: capture.isProcessing)
        .animation(.easeInOut(duration: DesignTokens.Motion.standard), value: capture.lastResult.fields)
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
        .listRowBackground(DesignTokens.Colors.surface)
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
            .pickerStyle(.menu)
            Picker("Size", selection: $editableFields.size) {
                ForEach(sizeOptions, id: \.self) { size in
                    Text("\(size) mL").tag(size)
                }
            }
            .pickerStyle(.menu)
            Stepper("Quantity: \(editableFields.quantity)", value: $editableFields.quantity, in: 1...500)
            Stepper("Minimum: \(editableFields.minimum)", value: $editableFields.minimum, in: 0...200)
            Picker("Aisle", selection: $editableFields.aisle) {
                Text("None").tag("")
                ForEach(locations.aisleOptions, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .pickerStyle(.menu)
            Picker("Shelf", selection: $editableFields.shelf) {
                Text("None").tag("")
                ForEach(locations.shelfOptions, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .pickerStyle(.menu)
            Picker("Row", selection: $editableFields.row) {
                Text("None").tag("")
                ForEach(locations.rowOptions, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .pickerStyle(.menu)
            Picker("Column", selection: $editableFields.column) {
                Text("None").tag("")
                ForEach(locations.columnOptions, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .pickerStyle(.menu)
        }
        .listRowBackground(DesignTokens.Colors.surface)
    }

    private var saveSection: some View {
        Section {
            Button(action: save) {
                Label("Save Item", systemImage: "tray.and.arrow.down")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(editableFields.normalizedFields == nil || editableFields.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .listRowBackground(DesignTokens.Colors.surface)
    }

    private var recognizedSection: some View {
        Section("Recognized text") {
            if capture.lastResult.fields.isEmpty {
                Text("Scan a label to see suggested fields.")
                    .foregroundStyle(.secondary)
            } else {
                Text("Tap suggestions to add them to a field, or tap again to remove something you've added.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                ForEach(suggestionFieldTypes, id: \.self, content: suggestionGroup(for:))
            }
        }
        .listRowBackground(DesignTokens.Colors.surface)
    }

    @ViewBuilder
    private func suggestionGroup(for fieldType: OCRCandidateField.FieldType) -> some View {
        let fieldOptions = options(for: fieldType)
        if fieldOptions.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text(label(for: fieldType))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                suggestionButtons(for: fieldOptions)
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func suggestionButtons(for options: [OCRCandidateField]) -> some View {
        ForEach(options, id: \.self) { option in
            suggestionButton(for: option)
        }
    }

    private func suggestionButton(for option: OCRCandidateField) -> some View {
        let isSelected = isCandidateSelected(option)
        return Button {
            withAnimation(DesignTokens.Motion.spring()) {
                if isSelected {
                    remove(option)
                } else {
                    apply(option)
                }
            }
            HapticsManager.shared.playSelectionChanged()
        } label: {
            HStack {
                Text(option.value)
                    .font(.body)
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundStyle(isSelected ? .tint : .secondary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .contentShape(RoundedRectangle(cornerRadius: DesignTokens.Radii.sm))
        .matchedGeometryEffect(id: option, in: suggestionNamespace, isSource: true)
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
                        if !item.locationDescription.isEmpty {
                            Text(item.locationDescription)
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
        .listRowBackground(DesignTokens.Colors.surface)
    }

    private var sortedInventory: [InventoryItem] {
        inventory.items.sorted { $0.updatedAt > $1.updatedAt }
    }

    private var sizeOptions: [Int] {
        var options = Set(inventory.availableSizes)
        options.insert(editableFields.size)
        if options.isEmpty {
            options.insert(InventoryItem.defaultSizes.first ?? 750)
        }
        return options.sorted()
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

    private var suggestionFieldTypes: [OCRCandidateField.FieldType] {
        [.name, .subName]
    }

    private func options(for fieldType: OCRCandidateField.FieldType) -> [OCRCandidateField] {
        var ocrOptions = capture.lastResult.fields
            .filter { $0.type == fieldType }
            .sorted { $0.confidence > $1.confidence }

        if fieldType == .name {
            let seeds = ([editableFields.name] + ocrOptions.map { $0.value })
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let databaseSuggestions = nameSuggestions(from: seeds)
                .filter { suggestion in
                    !ocrOptions.contains { existing in
                        existing.value.caseInsensitiveCompare(suggestion) == .orderedSame
                    }
                }
                .map { suggestion in
                    OCRCandidateField(type: .name, value: suggestion, confidence: 1)
                }

            ocrOptions.append(contentsOf: databaseSuggestions)
        }

        return ocrOptions
    }

    private func apply(_ candidate: OCRCandidateField) {
        switch candidate.type {
        case .name:
            let trimmed = candidate.value.trimmingCharacters(in: .whitespacesAndNewlines)
            if editableFields.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                editableFields.name = trimmed
            } else if !contains(candidate: trimmed, in: editableFields.name) {
                editableFields.name = editableFields.name.appendingSpacingIfNeeded() + trimmed
            }
        case .subName:
            let trimmed = candidate.value.trimmingCharacters(in: .whitespacesAndNewlines)
            if editableFields.subName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                editableFields.subName = trimmed
            } else if !contains(candidate: trimmed, in: editableFields.subName) {
                editableFields.subName = editableFields.subName.appendingSpacingIfNeeded() + trimmed
            }
        case .type:
            if let matchedType = normalizedType(from: candidate.value) {
                editableFields.type = matchedType
            }
        case .sizeML:
            if let size = parseSizeValue(from: candidate.value) {
                editableFields.size = size
            }
        }
    }

    private func remove(_ candidate: OCRCandidateField) {
        switch candidate.type {
        case .name:
            removeOccurrence(candidate.value, from: &editableFields.name)
        case .subName:
            removeOccurrence(candidate.value, from: &editableFields.subName)
        case .type, .sizeML:
            return
        }
    }

    private func removeOccurrence(_ candidate: String, from field: inout String) {
        let trimmedCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCandidate.isEmpty else { return }
        if let range = field.range(of: trimmedCandidate, options: [.caseInsensitive, .diacriticInsensitive]) {
            field.removeSubrange(range)
            let collapsed = field
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            field = collapsed
        }
    }

    private func isCandidateSelected(_ candidate: OCRCandidateField) -> Bool {
        switch candidate.type {
        case .name:
            return contains(candidate: candidate.value, in: editableFields.name)
        case .subName:
            return contains(candidate: candidate.value, in: editableFields.subName)
        case .type:
            guard let matchedType = normalizedType(from: candidate.value) else { return false }
            return editableFields.type == matchedType
        case .sizeML:
            guard let size = parseSizeValue(from: candidate.value) else { return false }
            return size == editableFields.size
        }
    }

    private func contains(candidate: String, in field: String) -> Bool {
        let trimmedCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCandidate.isEmpty else { return false }
        return field
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
            .contains(trimmedCandidate
                .folding(options: .diacriticInsensitive, locale: .current)
                .lowercased())
    }

    private func nameSuggestions(from seeds: [String], limit: Int = 6) -> [String] {
        guard !seeds.isEmpty else { return [] }
        var seen = Set<String>()
        var results: [String] = []
        let normalizedSeeds = seeds.map { seed -> String in
            seed.folding(options: .diacriticInsensitive, locale: .current)
                .lowercased()
        }
        .filter { !$0.isEmpty }

        guard !normalizedSeeds.isEmpty else { return [] }

        for item in inventory.items {
            let candidate = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !candidate.isEmpty else { continue }
            let lowered = candidate.folding(options: .diacriticInsensitive, locale: .current).lowercased()
            guard normalizedSeeds.contains(where: { lowered.contains($0) }) else { continue }
            if seen.insert(lowered).inserted {
                results.append(candidate)
            }
            if results.count >= limit { break }
        }

        return results
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
                    HapticsManager.shared.playSuccess()
                }
            }
        }
    }
}

private struct ProcessingBanner: View {
    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(.circular)
            VStack(alignment: .leading, spacing: 2) {
                Text("Processing scan")
                    .font(.subheadline.weight(.semibold))
                Text("This usually takes a second")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .background(
            Capsule(style: .continuous)
                .fill(DesignTokens.Colors.elevatedSurface)
                .shadow(color: DesignTokens.Shadow.card, radius: 12, x: 0, y: 6)
        )
        .padding(.horizontal)
    }
}

private struct EditableFields {
    var name: String = ""
    var subName: String = ""
    var type: String = InventoryItem.defaultTypes.last ?? "Other"
    var size: Int = InventoryItem.defaultSizes.first ?? 750
    var quantity: Int = 1
    var minimum: Int = 0
    var aisle: String = ""
    var shelf: String = ""
    var row: String = ""
    var column: String = ""

    init(from normalized: NormalizedFields? = nil) {
        if let normalized {
            name = normalized.name
            subName = normalized.subName
            type = normalized.type
            size = normalized.sizeML
            quantity = max(1, normalized.initialQuantity)
            minimum = normalized.minimum
            aisle = normalized.aisle
            shelf = normalized.shelf
            row = normalized.row
            column = normalized.column
        }
    }

    var normalizedFields: NormalizedFields? {
        guard size > 0 else { return nil }
        return NormalizedFields(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            subName: subName.trimmingCharacters(in: .whitespacesAndNewlines),
            type: type,
            sizeML: size,
            minimum: minimum,
            initialQuantity: quantity,
            aisle: aisle,
            shelf: shelf,
            row: row,
            column: column
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

private extension String {
    func appendingSpacingIfNeeded() -> String {
        guard !isEmpty else { return self }
        if let lastCharacter = last, lastCharacter.isWhitespace { return self }
        return self + " "
    }
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

    var captureSource: CaptureViewModel.Source {
        switch self {
        case .camera:
            return .camera
        case .photoLibrary:
            return .photoLibrary
        }
    }

}

private struct ImagePicker: UIViewControllerRepresentable {
    let source: ImagePickerSource
    let completion: (Data) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = source.sourceType
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
            guard let image = info[.originalImage] as? UIImage else { return }
            let compressedData = image.scaledJPEGData(maxDimension: 1600, compressionQuality: 0.7) ?? image.jpegData(compressionQuality: 0.75)
            guard let data = compressedData else { return }
            parent.completion(data)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
#endif

#if canImport(UIKit)
private extension UIImage {
    func scaledJPEGData(maxDimension: CGFloat, compressionQuality: CGFloat) -> Data? {
        autoreleasepool {
            let largestDimension = max(size.width, size.height)
            let targetScale = largestDimension > maxDimension ? maxDimension / largestDimension : 1
            if targetScale >= 0.999 { // No meaningful scaling required.
                return jpegData(compressionQuality: compressionQuality)
            }

            let targetSize = CGSize(width: size.width * targetScale, height: size.height * targetScale)
            let rendererFormat = UIGraphicsImageRendererFormat()
            rendererFormat.scale = 1
            rendererFormat.opaque = false
            let renderer = UIGraphicsImageRenderer(size: targetSize, format: rendererFormat)
            let scaledImage = renderer.image { _ in
                self.draw(in: CGRect(origin: .zero, size: targetSize))
            }
            return scaledImage.jpegData(compressionQuality: compressionQuality)
        }
    }
}
#endif
