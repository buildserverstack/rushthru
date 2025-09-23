import Foundation

#if canImport(LocalAuthentication)
import LocalAuthentication
#endif

public enum BiometricsKind: String, Sendable {
    case none
    case faceID
    case touchID
}

public enum LocalAuthError: Error, Sendable, Equatable {
    case notAvailable
    case failed
    case cancelled
}

public protocol LocalAuthProviding: Sendable {
    func supportedBiometrics() -> BiometricsKind
    func authenticate(reason: String) async throws
}

public struct NullLocalAuthProvider: LocalAuthProviding {
    public init() {}
    public func supportedBiometrics() -> BiometricsKind { .none }
    public func authenticate(reason: String) async throws {}
}

#if canImport(LocalAuthentication)
public struct LiveLocalAuthProvider: LocalAuthProviding {
    public init() {}

    public func supportedBiometrics() -> BiometricsKind {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        default: return .none
        }
    }

    public func authenticate(reason: String) async throws {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            throw LocalAuthError.notAvailable
        }
        return try await withCheckedThrowingContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, error in
                if success {
                    continuation.resume()
                } else if let laError = error as? LAError {
                    switch laError.code {
                    case .userCancel, .systemCancel:
                        continuation.resume(throwing: LocalAuthError.cancelled)
                    case .biometryNotAvailable, .biometryNotEnrolled, .biometryLockout:
                        continuation.resume(throwing: LocalAuthError.notAvailable)
                    default:
                        continuation.resume(throwing: LocalAuthError.failed)
                    }
                } else {
                    continuation.resume(throwing: LocalAuthError.failed)
                }
            }
        }
    }
}
#endif
