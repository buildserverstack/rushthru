import Foundation
import Combine
#if canImport(CryptoKit)
import CryptoKit
#endif
#if canImport(Security)
import Security
#endif

@MainActor
final class AuthService: ObservableObject {
    enum LockState {
        case locked
        case unlocked
    }

    @Published private(set) var state: LockState = .locked
    @Published private(set) var isLocked: Bool = true
    @Published private(set) var failedAttempts: Int = 0
    @Published private(set) var cooldownUntil: Date?
    @Published var autoLockMinutes: Int = 5
    @Published var biometricsEnabled: Bool = false

    private var pinHash: Data?
    private var pinSalt: Data?

    func bootstrap() async {
        // Placeholder for loading from persistence
        if pinHash == nil {
            state = .unlocked
            isLocked = false
        } else {
            state = .locked
            isLocked = true
        }
    }

    func setPIN(_ pin: String) {
        let salt = Self.randomSalt()
        pinHash = Self.hash(pin: pin, salt: salt)
        pinSalt = salt
        failedAttempts = 0
        cooldownUntil = nil
    }

    func verify(pin: String) async throws {
        if let cooldown = cooldownUntil, cooldown > Date() {
            throw AuthError.cooldownActive(until: cooldown)
        }
        guard let salt = pinSalt, let stored = pinHash else {
            throw AuthError.pinNotSet
        }
        let candidate = Self.hash(pin: pin, salt: salt)
        guard candidate == stored else {
            failedAttempts += 1
            if failedAttempts >= 5 {
                cooldownUntil = Date().addingTimeInterval(60)
            }
            throw AuthError.invalidPIN
        }
        failedAttempts = 0
        cooldownUntil = nil
        state = .unlocked
        isLocked = false
    }

    func lock() {
        state = .locked
        isLocked = true
    }

    func unlockForBiometrics() {
        state = .unlocked
        isLocked = false
    }

    func recordBackgroundLock() {
        lock()
    }

    func shouldAutoLock(lastInteraction: Date) -> Bool {
        Date().timeIntervalSince(lastInteraction) > Double(autoLockMinutes * 60)
    }

    private static func hash(pin: String, salt: Data) -> Data {
        #if canImport(CryptoKit)
        var hasher = SHA256()
        hasher.update(data: salt)
        hasher.update(data: Data(pin.utf8))
        return Data(hasher.finalize())
        #else
        return Data((salt + Data(pin.utf8)).prefix(32))
        #endif
    }

    private static func randomSalt() -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        #if canImport(Security)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        #else
        for idx in bytes.indices {
            bytes[idx] = UInt8.random(in: .min ... .max)
        }
        #endif
        return Data(bytes)
    }

    enum AuthError: Error, LocalizedError {
        case pinNotSet
        case invalidPIN
        case cooldownActive(until: Date)

        var errorDescription: String? {
            switch self {
            case .pinNotSet:
                return "PIN not configured"
            case .invalidPIN:
                return "Incorrect PIN"
            case .cooldownActive(let until):
                let formatter = DateFormatter()
                formatter.timeStyle = .short
                return "Locked until \(formatter.string(from: until))"
            }
        }
    }
}
