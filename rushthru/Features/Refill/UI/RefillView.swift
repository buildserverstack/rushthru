import SwiftUI
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif

struct RefillView: View {
    @EnvironmentObject private var refill: RefillViewModel
    @EnvironmentObject private var locations: LocationsViewModel
    @State private var selectedItem: InventoryItem?
    @State private var quantityMoved: Int = 1
    @State private var showAddManual = false
    @State private var showShelfScanner = false
    @State private var manualName: String = ""
    @State private var manualQuantity: Int = 1

    var body: some View {
        NavigationStack {
            List {
                shelfSuggestionsSection
                belowMinimumSection
                manualTasksSection
            }
            .listStyle(.insetGrouped)
            .animation(DesignTokens.Motion.spring(), value: refill.shelfSuggestions)
            .animation(DesignTokens.Motion.spring(), value: refill.refillItems)
            .animation(DesignTokens.Motion.spring(), value: refill.manualTasks)
            .sheet(item: $selectedItem) { item in
                NavigationStack {
                    Form {
                        Stepper("Moved to shelf: \(quantityMoved)", value: $quantityMoved, in: 1...200)
                    }
                    .navigationTitle(item.displayName)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { selectedItem = nil }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Strike") {
                                Task {
                                    await refill.strike(itemID: item.id, movedQuantity: quantityMoved)
                                    selectedItem = nil
                                }
                            }
                            .disabled(quantityMoved <= 0)
                        }
                    }
                }
            }
            .sheet(isPresented: $showShelfScanner) {
                RefillShelfScannerView()
                    .environmentObject(refill)
            }
            .sheet(isPresented: $showAddManual) {
                NavigationStack {
                    Form {
                        TextField("Item name", text: $manualName)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.words)
                        let suggestions = refill.suggestions(for: manualName)
                        if !suggestions.isEmpty {
                            Section("Suggestions") {
                                ForEach(suggestions) { suggestion in
                                    Button {
                                        manualName = suggestion.displayName
                                        let defaultQuantity = suggestion.minimum - suggestion.quantity
                                        manualQuantity = max(1, min(500, defaultQuantity))
                                    } label: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(suggestion.displayName)
                                                .font(.body)
                                                .foregroundStyle(.primary)
                                            Text("On hand: \(suggestion.quantity)  •  Min: \(suggestion.minimum)")
                                                .font(.footnote)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                        Stepper("Quantity needed: \(manualQuantity)", value: $manualQuantity, in: 1...500)
                    }
                    .navigationTitle("Add refill item")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                showAddManual = false
                                resetManualForm()
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Add") {
                                refill.addManualTask(name: manualName, quantity: manualQuantity)
                                showAddManual = false
                                resetManualForm()
                                HapticsManager.shared.playSuccess()
                            }
                            .disabled(manualName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
            }
            .navigationTitle("Refill List")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showShelfScanner = true
                        HapticsManager.shared.playSelectionChanged()
                    } label: {
                        Label("Scan", systemImage: "camera.viewfinder")
                    }
                    Button {
                        showAddManual = true
                        HapticsManager.shared.playSelectionChanged()
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
            .onChange(of: refill.shelfScanError) { error in
                guard error != nil else { return }
                HapticsManager.shared.playError()
            }
        }
    }

    private func resetManualForm() {
        manualName = ""
        manualQuantity = 1
    }

    @ViewBuilder
    private var shelfSuggestionsSection: some View {
        if refill.isScanningShelf || !refill.shelfSuggestions.isEmpty || refill.shelfScanError != nil {
            Section("Shelf scan suggestions") {
                shelfScanStatus
                shelfSuggestionRows
                shelfSuggestionFooter
            }
            .listRowBackground(DesignTokens.Colors.surface)
        }
    }

    @ViewBuilder
    private var shelfScanStatus: some View {
        if refill.isScanningShelf {
            HStack(spacing: 12) {
                ProgressView()
                Text("Analyzing shelf…")
            }
        }
        if let message = refill.shelfScanError {
            Text(message)
                .font(.footnote)
                .foregroundStyle(.red)
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private var shelfSuggestionRows: some View {
        ForEach(refill.shelfSuggestions) { suggestion in
            Button {
                withAnimation(DesignTokens.Motion.spring()) {
                    refill.applyShelfSuggestion(suggestion)
                }
                HapticsManager.shared.playSuccess()
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(suggestion.displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("Needed: \(suggestion.suggestedQuantity)  •  On shelf: \(suggestion.availableQuantity)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    suggestionCapacityText(for: suggestion)
                    suggestionConfidenceText(for: suggestion)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func suggestionCapacityText(for suggestion: ShelfSuggestion) -> some View {
        if suggestion.isCapacityBased {
            Text("Space detected for \(suggestion.suggestedQuantity) bottle\(suggestion.suggestedQuantity == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func suggestionConfidenceText(for suggestion: ShelfSuggestion) -> some View {
        if suggestion.confidence > 0 {
            Text("Confidence \(Int((suggestion.confidence * 100).rounded()))%")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var shelfSuggestionFooter: some View {
        if !refill.shelfSuggestions.isEmpty {
            Text("Tap a suggestion to add it to your refill list.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private var belowMinimumSection: some View {
        Section("Items below minimum") {
            if refill.refillItems.isEmpty {
                Text("Great! Everything is stocked.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(refill.refillItems) { item in
                    Button {
                        selectedItem = item
                        quantityMoved = max(1, item.minimum - item.quantity)
                        HapticsManager.shared.playSelectionChanged()
                    } label: {
                        VStack(alignment: .leading) {
                            Text(item.displayName)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text("Current: \(item.quantity) / Minimum: \(item.minimum)")
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
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .listRowBackground(DesignTokens.Colors.surface)
    }

    @ViewBuilder
    private var manualTasksSection: some View {
        Section("Manual refill items") {
            if refill.manualTasks.isEmpty {
                Text("Add items you plan to restock and strike them when done.")
                    .foregroundStyle(.secondary)
            } else {
                manualTaskRows
            }
        }
        .listRowBackground(DesignTokens.Colors.surface)
    }

    @ViewBuilder
    private var manualTaskRows: some View {
        ForEach(refill.manualTasks) { task in
            HStack {
                VStack(alignment: .leading) {
                    Text(task.name)
                        .font(.headline)
                    Text("Requested: \(task.quantity)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("Available: \(task.availableQuantity)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let storeName = locations.storeName(for: task.storeID) {
                        Text(storeName)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Strike") {
                    withAnimation(DesignTokens.Motion.spring()) {
                        refill.strikeManual(taskID: task.id)
                    }
                    HapticsManager.shared.playSuccess()
                }
                .buttonStyle(PrimaryButtonStyle(isCompact: true))
            }
        }
        .onDelete { indexSet in
            refill.removeManualTasks(at: indexSet)
        }
    }
}

struct RefillShelfScannerView: View {
    @EnvironmentObject private var refill: RefillViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var pickerItem: PhotosPickerItem?
    @State private var previewImage: Image?
    @State private var showCamera = false
    @State private var processingMessage: String?
    @State private var isLoadingImage = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                SurfaceCard {
                    ZStack {
                        RoundedRectangle(cornerRadius: DesignTokens.Radii.md)
                            .fill(DesignTokens.Colors.elevatedSurface)
                            .frame(height: 220)
                        if let previewImage {
                            previewImage
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: 220)
                                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radii.md))
                                .transition(.scale.combined(with: .opacity))
                        } else {
                            VStack(spacing: 8) {
                                Image(systemName: "camera.viewfinder")
                                    .font(.system(size: 42))
                                    .foregroundStyle(.secondary)
                                Text("Capture a shelf to suggest refills")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                            .transition(.opacity)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                if isLoadingImage {
                    ProgressView("Preparing image…")
                } else if refill.isScanningShelf {
                    ProgressView("Analyzing shelf…")
                }

                if let message = processingMessage ?? refill.shelfScanError {
                    Text(message)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.red)
                }

                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label("Choose from library", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())

                #if canImport(UIKit)
                Button {
                    showCamera = true
                } label: {
                    Label("Take photo", systemImage: "camera.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle(isCompact: true))
                .disabled(!CameraCaptureView.isCameraAvailable)
                #endif

                Spacer()
            }
            .padding()
            .navigationTitle("Scan Shelf")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        refill.clearShelfScanResults()
                        dismiss()
                    }
                }
            }
        }
        .onChange(of: pickerItem) { newValue in
            guard let newValue else { return }
            HapticsManager.shared.playSelectionChanged()
            loadPhoto(from: newValue)
        }
        .onChange(of: refill.shelfSuggestions) { suggestions in
            if !suggestions.isEmpty && !refill.isScanningShelf {
                HapticsManager.shared.playSuccess()
                dismiss()
            }
        }
        #if canImport(UIKit)
        .sheet(isPresented: $showCamera) {
            CameraCaptureView { data in
                showCamera = false
                guard let data else { return }
                Task { await processSelectedImage(data) }
            }
        }
        #endif
    }

    private func loadPhoto(from item: PhotosPickerItem) {
        processingMessage = nil
        isLoadingImage = true
        Task {
            do {
                if let data = try await item.loadTransferable(type: Data.self) {
                    await processSelectedImage(data)
                } else {
                    await MainActor.run {
                        processingMessage = "Unable to read the selected image."
                        isLoadingImage = false
                        HapticsManager.shared.playError()
                    }
                }
            } catch {
                await MainActor.run {
                    processingMessage = "Failed to load photo."
                    isLoadingImage = false
                    HapticsManager.shared.playError()
                }
            }
        }
    }

    private func processSelectedImage(_ data: Data) async {
        await refill.analyzeShelfImage(data)
        await MainActor.run {
            updatePreview(with: data)
            isLoadingImage = false
            if processingMessage != nil, refill.shelfScanError == nil {
                processingMessage = nil
                HapticsManager.shared.playSuccess()
            } else if refill.shelfScanError != nil {
                HapticsManager.shared.playError()
            }
        }
    }

    private func updatePreview(with data: Data) {
        #if canImport(UIKit)
        if let image = UIImage(data: data) {
            previewImage = Image(uiImage: image)
        }
        #endif
    }
}

#if canImport(UIKit)
private struct CameraCaptureView: UIViewControllerRepresentable {
    static var isCameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    var completion: (Data?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let completion: (Data?) -> Void

        init(completion: @escaping (Data?) -> Void) {
            self.completion = completion
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let image = info[.originalImage] as? UIImage
            let data = image?.jpegData(compressionQuality: 0.9)
            completion(data)
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            completion(nil)
            picker.dismiss(animated: true)
        }
    }
}
#endif

#Preview {
    let environment = AppEnvironment(preview: true)
    RefillView()
        .environmentObject(environment.refill)
        .environmentObject(environment.locations)
}
