import Foundation

#if canImport(CoreML)
import CoreML
#endif
#if canImport(Vision)
import Vision
#endif

/// Result wrapper for the DinoV3 recognizer. Although DinoV3 is primarily an
/// image representation model, we surface its detections as text observations
/// so the downstream capture pipeline can remain unchanged. When DinoV3 output
/// does not provide explicit text, we fall back to lightweight heuristics to
/// mirror the previous OCR behaviour.
public struct DinoV3TextObservation: Sendable, Equatable {
    public let text: String
    public let confidence: Float

    public init(text: String, confidence: Float) {
        self.text = text
        self.confidence = confidence
    }
}

public protocol DinoV3TextRecognizing: Sendable {
    func recognizeText(in imageData: Data) async throws -> [DinoV3TextObservation]
}

public struct NullDinoV3Recognizer: DinoV3TextRecognizing {
    public init() {}
    public func recognizeText(in imageData: Data) async throws -> [DinoV3TextObservation] {
        []
    }
}

#if canImport(Vision)
/// A lightweight integration point for the DinoV3 model. The production
/// implementation should load a CoreML-converted DinoV3 checkpoint and use its
/// embeddings to drive text extraction. Until that model is available we reuse
/// Vision's text recognizer as a compatibility shim so the rest of the app
/// continues to function while the Dino pipeline is integrated.
public final class DinoV3TextRecognizer: DinoV3TextRecognizing {
    private let fallbackRequest: VNRecognizeTextRequest

    public init(recognitionLevel: VNRequestTextRecognitionLevel = .fast) {
        fallbackRequest = VNRecognizeTextRequest(completionHandler: nil)
        fallbackRequest.recognitionLevel = recognitionLevel
        fallbackRequest.usesLanguageCorrection = true
    }

    public func recognizeText(in imageData: Data) async throws -> [DinoV3TextObservation] {
        let handler = VNImageRequestHandler(data: imageData)
        try handler.perform([fallbackRequest])
        let results = fallbackRequest.results ?? []
        return results.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return DinoV3TextObservation(text: candidate.string, confidence: candidate.confidence)
        }
    }
}
#else
public final class DinoV3TextRecognizer: DinoV3TextRecognizing {
    public init() {}
    public func recognizeText(in imageData: Data) async throws -> [DinoV3TextObservation] {
        []
    }
}
#endif
