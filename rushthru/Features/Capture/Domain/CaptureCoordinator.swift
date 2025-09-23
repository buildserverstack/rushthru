import Foundation

@MainActor
final class CaptureCoordinator: ObservableObject {
    struct PendingDuplicate: Identifiable, Equatable {
        let id = UUID()
        let existing: InventoryItem
        let proposed: NormalizedFields
    }

    enum Source {
        case camera
        case photoLibrary
    }

    @Published private(set) var lastResult: OCRResult = .empty
    @Published private(set) var draftFields: NormalizedFields = .default
    @Published private(set) var pendingDuplicate: PendingDuplicate?
    @Published var isProcessing: Bool = false
    @Published var errorMessage: String?

    private let inventoryService: InventoryService
    private let cameraRecognizer: DonutTextRecognizing
    private let galleryRecognizer: DonutTextRecognizing

    init(
        inventoryService: InventoryService,
        cameraRecognizer: DonutTextRecognizing,
        galleryRecognizer: DonutTextRecognizing
    ) {
        self.inventoryService = inventoryService
        self.cameraRecognizer = cameraRecognizer
        self.galleryRecognizer = galleryRecognizer
    }

    func bootstrap() async {}

    func process(imageData: Data, from source: Source) async {
        isProcessing = true
        defer { isProcessing = false }

        do {
            let recognizer = source == .photoLibrary ? galleryRecognizer : cameraRecognizer
            let observations = try await recognizer.recognizeText(in: imageData)
            let parsed = parse(observations: observations)
            lastResult = OCRResult(fields: parsed.fields)
            if let normalized = parsed.normalizedFields {
                draftFields = normalized
            }
            errorMessage = parsed.normalizedFields == nil ? "We couldn't read that label. Try again in brighter light." : nil
        } catch {
            errorMessage = "Scanning failed. Please try again."
            lastResult = .empty
        }
    }

    func process(fields: NormalizedFields) async {
        pendingDuplicate = nil
        errorMessage = nil

        if let match = inventoryService.existingItem(matching: fields.identity) {
            pendingDuplicate = PendingDuplicate(existing: match, proposed: fields)
            return
        }

        await createItem(from: fields)
    }

    func acceptDuplicateUpdate() async {
        guard let pendingDuplicate else { return }
        self.pendingDuplicate = nil
        await inventoryService.incrementQuantity(itemID: pendingDuplicate.existing.id, delta: pendingDuplicate.proposed.initialQuantity)
        resetDraft()
    }

    func createDuplicateItem() async {
        guard let pendingDuplicate else { return }
        self.pendingDuplicate = nil
        await createItem(from: pendingDuplicate.proposed)
    }

    func resetDraft() {
        draftFields = .default
        lastResult = .empty
        errorMessage = nil
    }

    private func createItem(from fields: NormalizedFields) async {
        guard let storeID = inventoryService.ensureActiveStoreID() else {
            errorMessage = "Select a store before saving items."
            return
        }

        let newItem = InventoryItem(
            name: fields.name,
            subName: fields.subName,
            type: fields.type,
            sizeML: fields.sizeML,
            quantity: fields.initialQuantity,
            minimum: fields.minimum,
            primaryLocationID: nil,
            storeID: storeID,
            aisle: fields.aisle,
            shelf: fields.shelf,
            row: fields.row,
            column: fields.column
        )
        await inventoryService.create(item: newItem)
        resetDraft()
    }

    private func parse(observations: [DonutTextObservation]) -> (normalizedFields: NormalizedFields?, fields: [OCRCandidateField]) {
        guard !observations.isEmpty else { return (nil, []) }

        let allText = observations.map { $0.text }.joined(separator: "\n")
        let lines = allText
            .components(separatedBy: CharacterSet.newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var candidateFields: [OCRCandidateField] = []
        var seenByType: [OCRCandidateField.FieldType: Set<String>] = [:]

        func register(_ value: String, for type: OCRCandidateField.FieldType, confidence: Double) {
            let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalizedValue.isEmpty else { return }
            var seen = seenByType[type] ?? []
            guard seen.insert(normalizedValue).inserted else { return }
            seenByType[type] = seen
            candidateFields.append(OCRCandidateField(type: type, value: value, confidence: confidence))
        }

        for (index, line) in lines.enumerated() {
            let confidence = Double(observations[min(index, observations.count - 1)].confidence)
            if index == 0 {
                register(line, for: .name, confidence: confidence)
            } else {
                register(line, for: .subName, confidence: confidence)
                register(line, for: .name, confidence: confidence * 0.85)
            }
        }

        let loweredText = allText.lowercased()
        let knownTypes = inventoryService.availableTypes
        var detectedTypes: [String] = []
        for typeName in knownTypes {
            let token = typeName.lowercased()
            if loweredText.contains(token) {
                detectedTypes.append(typeName)
            }
        }
        if detectedTypes.isEmpty {
            detectedTypes = [knownTypes.last ?? "Other"]
        }
        for (index, itemType) in detectedTypes.enumerated() {
            let confidence = max(0.3, 0.9 - Double(index) * 0.1)
            register(itemType, for: .type, confidence: confidence)
        }

        var volumeCandidates: [Int] = []
        let pattern = "(\\d+(?:\\.\\d+)?)\\s*(ml|milliliter|millilitre|l|liter|litre)?"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let range = NSRange(location: 0, length: loweredText.utf16.count)
            regex.enumerateMatches(in: loweredText, options: [], range: range) { match, _, _ in
                guard let match = match,
                      let valueRange = Range(match.range(at: 1), in: loweredText) else { return }
                let unitRange = Range(match.range(at: 2), in: loweredText)
                let valueString = String(loweredText[valueRange])
                guard let value = Double(valueString) else { return }
                let unit = unitRange.map { String(loweredText[$0]) } ?? "ml"
                let milliliters: Int
                if unit.hasPrefix("l") {
                    milliliters = Int((value * 1000).rounded())
                } else {
                    milliliters = Int(value.rounded())
                }
                if !volumeCandidates.contains(milliliters) {
                    volumeCandidates.append(milliliters)
                }
            }
        }
        if volumeCandidates.isEmpty {
            volumeCandidates.append(750)
        }
        for (index, volume) in volumeCandidates.enumerated() {
            let confidence = max(0.3, 0.75 - Double(index) * 0.1)
            register("\(volume)", for: .sizeML, confidence: confidence)
        }

        let bestName = candidateFields.first(where: { $0.type == .name })?.value.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !bestName.isEmpty else {
            return (nil, candidateFields)
        }
        let bestSubName = candidateFields.first(where: { $0.type == .subName })?.value.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let typeValue = candidateFields.first(where: { $0.type == .type })?.value ?? (inventoryService.availableTypes.last ?? "Other")
        let normalizedType = inventoryService.matchingType(for: typeValue) ?? typeValue
        let bestSize = volumeCandidates.first ?? 750

        let normalized = NormalizedFields(
            name: bestName,
            subName: bestSubName,
            type: normalizedType,
            sizeML: bestSize,
            minimum: 0,
            initialQuantity: 1
        )

        return (normalized, candidateFields)
    }
}

struct NormalizedFields: Equatable {
    var name: String
    var subName: String
    var type: String
    var sizeML: Int
    var minimum: Int
    var initialQuantity: Int
    var aisle: String
    var shelf: String
    var row: String
    var column: String

    static let `default` = NormalizedFields(name: "", subName: "", type: InventoryItem.defaultTypes.last ?? "Other", sizeML: InventoryItem.defaultSizes.first ?? 750, minimum: 0, initialQuantity: 1)

    init(name: String, subName: String, type: String, sizeML: Int, minimum: Int, initialQuantity: Int, aisle: String = "", shelf: String = "", row: String = "", column: String = "") {
        self.name = name
        self.subName = subName
        self.type = type
        self.sizeML = sizeML
        self.minimum = minimum
        self.initialQuantity = initialQuantity
        self.aisle = aisle
        self.shelf = shelf
        self.row = row
        self.column = column
    }

    var identity: ItemIdentity {
        ItemIdentity(name: name, type: type, sizeML: sizeML)
    }
}
