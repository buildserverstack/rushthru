import Foundation

#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

public enum DocumentPickerAction: Sendable {
    case export(url: URL)
    case `import`(allowedContentTypes: [String])
}

public protocol DocumentPickerHandling: Sendable {
    func presentPicker(for action: DocumentPickerAction) async throws
}

public struct NullDocumentPickerHandler: DocumentPickerHandling {
    public init() {}
    public func presentPicker(for action: DocumentPickerAction) async throws {}
}

#if canImport(UIKit)
import UIKit

public final class LiveDocumentPickerHandler: NSObject, DocumentPickerHandling, UIDocumentPickerDelegate {
    private weak var presenter: UIViewController?
    private var continuation: CheckedContinuation<Void, Error>?

    public init(presenter: UIViewController?) {
        self.presenter = presenter
        super.init()
    }

    public func presentPicker(for action: DocumentPickerAction) async throws {
        guard let presenter else { throw NSError(domain: "DocumentPicker", code: -1) }

        let controller: UIDocumentPickerViewController
        switch action {
        case .export(let url):
            controller = UIDocumentPickerViewController(forExporting: [url])
        case .import(let allowedTypes):
            let contentTypes: [UTType]
            if allowedTypes.isEmpty {
                contentTypes = [.item]
            } else {
                contentTypes = allowedTypes.compactMap { UTType($0) }
            }
            controller = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes)
        }

        controller.delegate = self
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            presenter.present(controller, animated: true)
        }
    }

    public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        continuation?.resume()
        continuation = nil
    }

    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        continuation?.resume()
        continuation = nil
    }
}
#endif
