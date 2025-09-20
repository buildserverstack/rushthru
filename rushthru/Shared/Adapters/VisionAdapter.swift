import Foundation

#if canImport(Vision)
import Vision
#endif

/// Normalized result from the OCR adapter. This mirrors the downstream capture
/// pipeline expectations without committing to Vision-specific types.
public struct RecognizedTextObservation: Sendable, Equatable {
    public let text: String
    public let confidence: Float

    public init(text: String, confidence: Float) {
        self.text = text
        self.confidence = confidence
    }
}

public protocol VisionTextRecognizing: Sendable {
    func recognizeText(in imageData: Data) async throws -> [RecognizedTextObservation]
}

public struct NullVisionRecognizer: VisionTextRecognizing {
    public init() {}
    public func recognizeText(in imageData: Data) async throws -> [RecognizedTextObservation] {
        []
    }
}

#if canImport(Vision)
public final class VisionTextRecognizer: VisionTextRecognizing {
    private let request: VNRecognizeTextRequest

    public init(recognitionLevel: VNRequestTextRecognitionLevel = .fast) {
        request = VNRecognizeTextRequest(completionHandler: nil)
        request.recognitionLevel = recognitionLevel
        request.usesLanguageCorrection = true
    }

    public func recognizeText(in imageData: Data) async throws -> [RecognizedTextObservation] {
        let handler = VNImageRequestHandler(data: imageData)
        try handler.perform([request])
        let results = request.results ?? []
        return results.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return RecognizedTextObservation(text: candidate.string, confidence: candidate.confidence)
        }
    }
}
#endif
