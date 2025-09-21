import Foundation

@MainActor
final class CaptureCoordinator: ObservableObject {
    struct PendingDuplicate: Identifiable, Equatable {
        let id = UUID()
        let existing: InventoryItem
        let proposed: NormalizedFields
    }

    @Published private(set) var lastResult: OCRResult = .empty
    @Published private(set) var draftFields: NormalizedFields = .default
    @Published private(set) var pendingDuplicate: PendingDuplicate?
    @Published var isProcessing: Bool = false
    @Published var errorMessage: String?

    private let inventoryService: InventoryService
    private let visionRecognizer: VisionTextRecognizing

    init(inventoryService: InventoryService, visionRecognizer: VisionTextRecognizing) {
        self.inventoryService = inventoryService
        self.visionRecognizer = visionRecognizer
    }

    func bootstrap() async {}

    func process(imageData: Data) async {
        isProcessing = true
        defer { isProcessing = false }

        do {
            let observations = try await visionRecognizer.recognizeText(in: imageData)
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
        let newItem = InventoryItem(
            name: fields.name,
            subName: fields.subName,
            type: fields.type,
            sizeML: fields.sizeML,
            quantity: fields.initialQuantity,
            minimum: fields.minimum,
            primaryLocationID: nil
        )
        await inventoryService.create(item: newItem)
        resetDraft()
    }

    private func parse(observations: [RecognizedTextObservation]) -> (normalizedFields: NormalizedFields?, fields: [OCRCandidateField]) {
        guard !observations.isEmpty else { return (nil, []) }

        let allText = observations.map { $0.text }.joined(separator: "\n")
        let lines = allText
            .components(separatedBy: CharacterSet.newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let name = lines.first ?? ""
        let subName = lines.dropFirst().first ?? ""
        let type = inferType(from: allText)
        let sizeML = extractVolume(from: allText) ?? 750

        var candidateFields: [OCRCandidateField] = []
        if !name.isEmpty {
            candidateFields.append(OCRCandidateField(type: .name, value: name, confidence: Double(observations.first?.confidence ?? 0)))
        }
        if !subName.isEmpty {
            candidateFields.append(OCRCandidateField(type: .subName, value: subName, confidence: Double(observations.dropFirst().first?.confidence ?? observations.first?.confidence ?? 0)))
        }
        candidateFields.append(OCRCandidateField(type: .type, value: type.displayName, confidence: 0.7))
        candidateFields.append(OCRCandidateField(type: .sizeML, value: "\(sizeML)", confidence: 0.6))

        let normalized = name.isEmpty ? nil : NormalizedFields(
            name: name,
            subName: subName,
            type: type,
            sizeML: sizeML,
            minimum: 0,
            initialQuantity: 1
        )

        return (normalized, candidateFields)
    }

    private func extractVolume(from text: String) -> Int? {
        let lowered = text.lowercased()
        let pattern = "(\\d+(?:\\.\\d+)?)\\s*(ml|milliliter|millilitre|l|liter|litre)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(location: 0, length: lowered.utf16.count)
        guard let match = regex.firstMatch(in: lowered, options: [], range: range) else { return nil }
        guard let valueRange = Range(match.range(at: 1), in: lowered),
              let unitRange = Range(match.range(at: 2), in: lowered) else { return nil }
        let valueString = String(lowered[valueRange])
        guard let value = Double(valueString) else { return nil }
        let unit = String(lowered[unitRange])
        if unit.hasPrefix("l") {
            return Int((value * 1000).rounded())
        } else {
            return Int(value.rounded())
        }
    }

    private func inferType(from text: String) -> InventoryItem.ItemType {
        let lowered = text.lowercased()
        for type in InventoryItem.ItemType.allCases where type != .other {
            if lowered.contains(type.rawValue) {
                return type
            }
        }
        return .other
    }
}

struct NormalizedFields: Equatable {
    var name: String
    var subName: String
    var type: InventoryItem.ItemType
    var sizeML: Int
    var minimum: Int
    var initialQuantity: Int

    static let `default` = NormalizedFields(name: "", subName: "", type: .other, sizeML: 750, minimum: 0, initialQuantity: 1)

    init(name: String, subName: String, type: InventoryItem.ItemType, sizeML: Int, minimum: Int, initialQuantity: Int) {
        self.name = name
        self.subName = subName
        self.type = type
        self.sizeML = sizeML
        self.minimum = minimum
        self.initialQuantity = initialQuantity
    }

    var identity: ItemIdentity {
        ItemIdentity(name: name, type: type, sizeML: sizeML)
    }
}
