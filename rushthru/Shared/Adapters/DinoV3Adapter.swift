import Foundation

#if canImport(CoreML)
import CoreML
#endif
#if canImport(Vision)
import Vision
#endif
#if canImport(MLKitTextRecognition) && canImport(MLKitVision) && canImport(UIKit)
import MLKitTextRecognition
import MLKitVision
import UIKit
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

#if canImport(MLKitTextRecognition) && canImport(MLKitVision) && canImport(UIKit)
public final class MLKitTextRecognizerAdapter: DonutTextRecognizing {
    private let recognizer: TextRecognizer
    private let fallback: DonutTextRecognizing

    public init(fallback: DonutTextRecognizing) {
        self.recognizer = TextRecognizer.textRecognizer()
        self.fallback = fallback
    }

    public func recognizeText(in imageData: Data) async throws -> [DonutTextObservation] {
        guard let image = UIImage(data: imageData) else {
            return try await fallback.recognizeText(in: imageData)
        }

        let visionImage = VisionImage(image: image)
        visionImage.orientation = image.imageOrientation

        return try await withCheckedThrowingContinuation { continuation in
            recognizer.process(visionImage) { text, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let text else {
                    continuation.resume(returning: [])
                    return
                }

                var observations: [DonutTextObservation] = []
                for block in text.blocks {
                    for line in block.lines {
                        let trimmed = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { continue }
                        observations.append(DonutTextObservation(text: trimmed, confidence: 1.0))
                    }
                }

                continuation.resume(returning: observations)
            }
        }
    }
}
#else
public final class MLKitTextRecognizerAdapter: DonutTextRecognizing {
    private let fallback: DonutTextRecognizing

    public init(fallback: DonutTextRecognizing) {
        self.fallback = fallback
    }

    public func recognizeText(in imageData: Data) async throws -> [DonutTextObservation] {
        try await fallback.recognizeText(in: imageData)
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

protocol ShelfRecognizing: Sendable {
    func analyzeShelf(imageData: Data, inventory: [ShelfInventorySnapshot]) async throws -> [ShelfRecognitionCandidate]
}

struct ShelfInventorySnapshot: Sendable {
    let id: UUID
    let displayName: String
    let quantity: Int
    let minimum: Int

    var isBelowMinimum: Bool { quantity < minimum }

    init(id: UUID, displayName: String, quantity: Int, minimum: Int) {
        self.id = id
        self.displayName = displayName
        self.quantity = quantity
        self.minimum = minimum
    }
}

extension ShelfInventorySnapshot {
    init(item: InventoryItem) {
        self.init(
            id: item.id,
            displayName: item.displayName,
            quantity: item.quantity,
            minimum: item.minimum
        )
    }
}

struct NullShelfRecognizer: ShelfRecognizing {
    init() {}
    func analyzeShelf(imageData: Data, inventory: [ShelfInventorySnapshot]) async throws -> [ShelfRecognitionCandidate] {
        []
    }
}

#if canImport(Vision)
final class DinoV3ShelfRecognizer: ShelfRecognizing {
    private let textRequest: VNRecognizeTextRequest
    private static let maxRecognizedLines = 64
    #if canImport(MLKitTextRecognition) && canImport(MLKitVision) && canImport(UIKit)
    private let mlKitRecognizer: TextRecognizer
    #endif

    init(recognitionLevel: VNRequestTextRecognitionLevel = .fast) {
        textRequest = VNRecognizeTextRequest(completionHandler: nil)
        textRequest.recognitionLevel = recognitionLevel
        textRequest.usesLanguageCorrection = true
        #if canImport(MLKitTextRecognition) && canImport(MLKitVision) && canImport(UIKit)
        mlKitRecognizer = TextRecognizer.textRecognizer()
        #endif
    }

    func analyzeShelf(imageData: Data, inventory: [ShelfInventorySnapshot]) async throws -> [ShelfRecognitionCandidate] {
        guard !inventory.isEmpty else { return [] }

        var recognizedLines = try await extractRecognizedLines(from: imageData)
        if recognizedLines.count > Self.maxRecognizedLines {
            recognizedLines.removeSubrange(Self.maxRecognizedLines...)
        }

        var matches: [ShelfRecognitionCandidate] = []
        var seenItemIDs = Set<UUID>()

        func normalizedTokens(for text: String) -> Set<String> {
            let normalized = ItemIdentity.normalize(text)
            return Set(normalized.split(separator: " ").map(String.init))
        }

        let inventoryTokens: [(item: ShelfInventorySnapshot, tokens: Set<String>)] = inventory.compactMap { item in
            let tokens = normalizedTokens(for: item.displayName)
            return tokens.isEmpty ? nil : (item, tokens)
        }

        for recognized in recognizedLines {
            let candidateTokens = normalizedTokens(for: recognized.text)
            guard !candidateTokens.isEmpty else { continue }

            var bestMatch: (item: ShelfInventorySnapshot, overlap: Double)?
            for entry in inventoryTokens {
                let overlap = Double(candidateTokens.intersection(entry.tokens).count)
                let candidateCount = Double(candidateTokens.count)
                let score = candidateCount > 0 ? overlap / candidateCount : 0
                if score > 0.3 {
                    if let existing = bestMatch {
                        if score > existing.overlap {
                            bestMatch = (entry.item, score)
                        }
                    } else {
                        bestMatch = (entry.item, score)
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
                    confidence: recognized.confidence
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

    private func extractRecognizedLines(from imageData: Data) async throws -> [RecognizedLine] {
        #if canImport(MLKitTextRecognition) && canImport(MLKitVision) && canImport(UIKit)
        if let mlKitLines = try await decodeUsingMLKit(imageData: imageData), !mlKitLines.isEmpty {
            return mlKitLines
        }
        #endif

        let handler = VNImageRequestHandler(data: imageData)
        try handler.perform([textRequest])
        let observations = textRequest.results ?? []

        return observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let trimmed = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return RecognizedLine(text: trimmed, confidence: Double(observation.confidence))
        }
    }

    private struct RecognizedLine: Sendable {
        let text: String
        let confidence: Double
    }

    #if canImport(MLKitTextRecognition) && canImport(MLKitVision) && canImport(UIKit)
    private func decodeUsingMLKit(imageData: Data) async throws -> [RecognizedLine]? {
        try await withCheckedThrowingContinuation { continuation in
            autoreleasepool {
                guard let image = UIImage(data: imageData) else {
                    continuation.resume(returning: [])
                    return
                }

                let visionImage = VisionImage(image: image)
                visionImage.orientation = image.imageOrientation

                mlKitRecognizer.process(visionImage) { text, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }

                    guard let text else {
                        continuation.resume(returning: [])
                        return
                    }

                    var results: [RecognizedLine] = []
                    results.reserveCapacity(text.blocks.count * 2)
                    for block in text.blocks {
                        for line in block.lines {
                            let trimmed = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { continue }
                            results.append(RecognizedLine(text: trimmed, confidence: 0.85))
                            if results.count >= Self.maxRecognizedLines {
                                continuation.resume(returning: results)
                                return
                            }
                        }
                    }
                    continuation.resume(returning: results)
                }
            }
        }
    }
    #endif
}
#else
final class DinoV3ShelfRecognizer: ShelfRecognizing {
    init() {}
    func analyzeShelf(imageData: Data, inventory: [ShelfInventorySnapshot]) async throws -> [ShelfRecognitionCandidate] {
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
