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
    @Published private(set) var hasPIN: Bool = false
    @Published private(set) var failedAttempts: Int = 0
    @Published private(set) var cooldownUntil: Date?
    @Published var autoLockMinutes: Int = 5 {
        didSet {
            guard hasBootstrapped, !isApplyingSettings else { return }
            updateSettings { $0.autoLockMinutes = autoLockMinutes }
        }
    }
    @Published var biometricsEnabled: Bool = false {
        didSet {
            guard hasBootstrapped, !isApplyingSettings else { return }
            updateSettings { $0.biometricsEnabled = biometricsEnabled }
        }
    }

    private let database: DatabaseManager
    private var settings: AppSettings = .initial
    private var isApplyingSettings = false
    private var hasBootstrapped = false

    init(database: DatabaseManager = .shared) {
        self.database = database
    }

    func bootstrap() async {
        var stored = database.loadSettings()
        if let cooldown = stored.cooldownUntil, cooldown <= Date() {
            stored.cooldownUntil = nil
            stored.failedAttempts = 0
            database.save(settings: stored)
        }

        isApplyingSettings = true
        settings = stored
        failedAttempts = stored.failedAttempts
        cooldownUntil = stored.cooldownUntil
        autoLockMinutes = stored.autoLockMinutes
        biometricsEnabled = stored.biometricsEnabled
        hasPIN = stored.pinHash != nil
        if hasPIN {
            lock()
        } else {
            state = .unlocked
            isLocked = false
        }
        isApplyingSettings = false
        hasBootstrapped = true
    }

    func setPIN(_ pin: String) {
        let salt = Self.randomSalt()
        let hash = Self.hash(pin: pin, salt: salt)
        failedAttempts = 0
        cooldownUntil = nil
        hasPIN = true
        updateSettings { settings in
            settings.pinHash = hash
            settings.pinSalt = salt
            settings.failedAttempts = 0
            settings.cooldownUntil = nil
        }
        lock()
    }

    func verify(pin: String) async throws {
        if let cooldown = cooldownUntil, cooldown <= Date() {
            failedAttempts = 0
            cooldownUntil = nil
            updateSettings { settings in
                settings.failedAttempts = 0
                settings.cooldownUntil = nil
            }
        }
        if let cooldown = cooldownUntil, cooldown > Date() {
            throw AuthError.cooldownActive(until: cooldown)
        }
        guard let salt = settings.pinSalt, let stored = settings.pinHash else {
            throw AuthError.pinNotSet
        }
        let candidate = Self.hash(pin: pin, salt: salt)
        guard candidate == stored else {
            let newAttempts = failedAttempts + 1
            failedAttempts = newAttempts
            let newCooldown: Date?
            if newAttempts >= 5 {
                let cooldown = Date().addingTimeInterval(60)
                cooldownUntil = cooldown
                newCooldown = cooldown
            } else {
                cooldownUntil = nil
                newCooldown = nil
            }
            updateSettings { settings in
                settings.failedAttempts = newAttempts
                settings.cooldownUntil = newCooldown
            }
            throw AuthError.invalidPIN
        }
        failedAttempts = 0
        cooldownUntil = nil
        updateSettings { settings in
            settings.failedAttempts = 0
            settings.cooldownUntil = nil
        }
        state = .unlocked
        isLocked = false
        hasPIN = true
    }

    func lock() {
        guard hasPIN else { return }
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

    func clearPIN() {
        failedAttempts = 0
        cooldownUntil = nil
        hasPIN = false
        updateSettings { settings in
            settings.pinHash = nil
            settings.pinSalt = nil
            settings.failedAttempts = 0
            settings.cooldownUntil = nil
        }
        state = .unlocked
        isLocked = false
    }

    func shouldAutoLock(lastInteraction: Date) -> Bool {
        guard hasPIN else { return false }
        return Date().timeIntervalSince(lastInteraction) > Double(autoLockMinutes * 60)
    }

    private func updateSettings(_ update: (inout AppSettings) -> Void) {
        update(&settings)
        database.save(settings: settings)
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
