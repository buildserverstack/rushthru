import Foundation

#if canImport(CoreML)
import CoreML
#endif
#if canImport(Vision)
import Vision
#endif

/// Observation wrapper emitted by the Donut-small recognizer. The production
/// build is expected to bundle the Donut-small CoreML checkpoint; until it is
/// available at runtime we fall back to the system Vision recognizer while
/// keeping the interface stable for easy swapping once the model ships.
public struct DonutTextObservation: Sendable, Equatable {
    public let text: String
    public let confidence: Float

    public init(text: String, confidence: Float) {
        self.text = text
        self.confidence = confidence
    }
}

public protocol DonutTextRecognizing: Sendable {
    func recognizeText(in imageData: Data) async throws -> [DonutTextObservation]
}

public struct NullDonutTextRecognizer: DonutTextRecognizing {
    public init() {}
    public func recognizeText(in imageData: Data) async throws -> [DonutTextObservation] {
        []
    }
}

#if canImport(Vision)
public final class DonutSmallTextRecognizer: DonutTextRecognizing {
    private let fallbackRequest: VNRecognizeTextRequest
    #if canImport(CoreML)
    private let model: MLModel?
    #endif

    public init(recognitionLevel: VNRequestTextRecognitionLevel = .fast) {
        fallbackRequest = VNRecognizeTextRequest(completionHandler: nil)
        fallbackRequest.recognitionLevel = recognitionLevel
        fallbackRequest.usesLanguageCorrection = true
        #if canImport(CoreML)
        if let url = Bundle.main.url(forResource: "donut_small", withExtension: "mlmodelc") {
            model = try? MLModel(contentsOf: url)
        } else {
            model = nil
        }
        #endif
    }

    public func recognizeText(in imageData: Data) async throws -> [DonutTextObservation] {
        #if canImport(CoreML)
        if let model {
            // Placeholder: integrate Donut-small inference once the compiled model
            // is checked in. We still run the Vision fallback so the pipeline is
            // functional during development.
            _ = model
        }
        #endif
        let handler = VNImageRequestHandler(data: imageData)
        try handler.perform([fallbackRequest])
        let results = fallbackRequest.results ?? []
        return results.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return DonutTextObservation(text: candidate.string, confidence: candidate.confidence)
        }
    }
}
#else
public final class DonutSmallTextRecognizer: DonutTextRecognizing {
    public init() {}
    public func recognizeText(in imageData: Data) async throws -> [DonutTextObservation] {
        []
    }
}
#endif

public struct ShelfRecognitionCandidate: Identifiable, Equatable {
    public let id: UUID
    public let itemID: UUID?
    public let name: String
    public let availableQuantity: Int
    public let suggestedQuantity: Int
    public let confidence: Double

    public init(id: UUID = UUID(), itemID: UUID?, name: String, availableQuantity: Int, suggestedQuantity: Int, confidence: Double) {
        self.id = id
        self.itemID = itemID
        self.name = name
        self.availableQuantity = availableQuantity
        self.suggestedQuantity = suggestedQuantity
        self.confidence = confidence
    }
}

public protocol ShelfRecognizing: Sendable {
    func analyzeShelf(imageData: Data, inventory: [InventoryItem]) async throws -> [ShelfRecognitionCandidate]
}

public struct NullShelfRecognizer: ShelfRecognizing {
    public init() {}
    public func analyzeShelf(imageData: Data, inventory: [InventoryItem]) async throws -> [ShelfRecognitionCandidate] {
        []
    }
}

#if canImport(Vision)
public final class DinoV3ShelfRecognizer: ShelfRecognizing {
    private let textRequest: VNRecognizeTextRequest

    public init(recognitionLevel: VNRequestTextRecognitionLevel = .fast) {
        textRequest = VNRecognizeTextRequest(completionHandler: nil)
        textRequest.recognitionLevel = recognitionLevel
        textRequest.usesLanguageCorrection = true
    }

    public func analyzeShelf(imageData: Data, inventory: [InventoryItem]) async throws -> [ShelfRecognitionCandidate] {
        guard !inventory.isEmpty else { return [] }

        let handler = VNImageRequestHandler(data: imageData)
        try handler.perform([textRequest])
        let observations = textRequest.results ?? []

        var matches: [ShelfRecognitionCandidate] = []
        var seenItemIDs = Set<UUID>()

        func normalizedTokens(for text: String) -> Set<String> {
            let normalized = ItemIdentity.normalize(text)
            return Set(normalized.split(separator: " ").map(String.init))
        }

        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let candidateTokens = normalizedTokens(for: candidate.string)
            guard !candidateTokens.isEmpty else { continue }

            var bestMatch: (item: InventoryItem, overlap: Double)?
            for item in inventory {
                let itemTokens = normalizedTokens(for: item.displayName)
                guard !itemTokens.isEmpty else { continue }
                let overlap = Double(candidateTokens.intersection(itemTokens).count)
                let candidateCount = Double(candidateTokens.count)
                let score = candidateCount > 0 ? overlap / candidateCount : 0
                if score > 0.3 { // basic threshold to filter noise
                    if let existing = bestMatch {
                        if score > existing.overlap {
                            bestMatch = (item, score)
                        }
                    } else {
                        bestMatch = (item, score)
                    }
                }
            }

            guard let match = bestMatch else { continue }
            guard !seenItemIDs.contains(match.item.id) else { continue }
            let needed = max(0, match.item.minimum - match.item.quantity)
            guard needed > 0 else { continue }
            seenItemIDs.insert(match.item.id)
            matches.append(
                ShelfRecognitionCandidate(
                    itemID: match.item.id,
                    name: match.item.displayName,
                    availableQuantity: match.item.quantity,
                    suggestedQuantity: needed,
                    confidence: Double(observation.confidence)
                )
            )
        }

        if matches.isEmpty {
            let belowMinimum = inventory.filter { $0.isBelowMinimum }
            matches = belowMinimum.map { item in
                ShelfRecognitionCandidate(
                    itemID: item.id,
                    name: item.displayName,
                    availableQuantity: item.quantity,
                    suggestedQuantity: max(1, item.minimum - item.quantity),
                    confidence: 0.25
                )
            }
        }

        return matches.sorted { lhs, rhs in
            if lhs.confidence == rhs.confidence {
                return lhs.suggestedQuantity > rhs.suggestedQuantity
            }
            return lhs.confidence > rhs.confidence
        }
    }
}
#else
public final class DinoV3ShelfRecognizer: ShelfRecognizing {
    public init() {}
    public func analyzeShelf(imageData: Data, inventory: [InventoryItem]) async throws -> [ShelfRecognitionCandidate] {
        inventory
            .filter { $0.isBelowMinimum }
            .map { item in
                ShelfRecognitionCandidate(
                    itemID: item.id,
                    name: item.displayName,
                    availableQuantity: item.quantity,
                    suggestedQuantity: max(1, item.minimum - item.quantity),
                    confidence: 0.2
                )
            }
    }
}
#endif
