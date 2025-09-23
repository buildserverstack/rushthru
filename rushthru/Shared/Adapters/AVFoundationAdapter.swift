import Foundation

#if canImport(AVFoundation)
@preconcurrency import AVFoundation
#endif

/// Abstracts camera session management so the capture feature can be tested without
/// touching AVFoundation in-process. The concrete implementation is injected at the
/// app level and uses the system camera APIs on device builds.
public protocol CameraSessionManaging {
    func startSession() async
    func stopSession()
    func setTorch(enabled: Bool) async throws
}

/// Default no-op adapter used for previews and unit tests when AVFoundation is not
/// available (such as macOS Catalyst or Swift Package builds without iOS SDK).
public struct NullCameraSessionManager: CameraSessionManaging {
    public init() {}
    public func startSession() async {}
    public func stopSession() {}
    public func setTorch(enabled: Bool) async throws {}
}

#if canImport(AVFoundation)
public final class LiveCameraSessionManager: NSObject, CameraSessionManaging {
    private let session: AVCaptureSession
    private let queue = DispatchQueue(label: "camera.session.queue")

    public override init() {
        self.session = AVCaptureSession()
        super.init()
    }

    public func startSession() async {
        let session = self.session
        let queue = self.queue
        await withCheckedContinuation { continuation in
            queue.async {
                if !session.isRunning {
                    session.startRunning()
                }
                continuation.resume()
            }
        }
    }

    public func stopSession() {
        let session = self.session
        let queue = self.queue
        queue.async {
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    public func setTorch(enabled: Bool) async throws {
        let queue = self.queue
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    guard let device = AVCaptureDevice.default(for: .video),
                          device.hasTorch else {
                        continuation.resume()
                        return
                    }
                    try device.lockForConfiguration()
                    device.torchMode = enabled ? .on : .off
                    device.unlockForConfiguration()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
#endif
