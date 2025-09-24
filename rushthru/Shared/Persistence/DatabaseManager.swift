import Foundation

#if canImport(GRDB)
import GRDB
#endif

/// Provides a unified interface for interacting with the on-device SQLite database.
/// The production build links against GRDB. For unit testing or Linux builds the
/// fallback in-memory store keeps the code compiling without GRDB.
@MainActor
final class DatabaseManager {
    static let shared = DatabaseManager()

    #if canImport(GRDB)
    let dbQueue: DatabaseWriter
    #else
    private static let settingsKey = "app_settings"
    private let defaults: UserDefaults
    private var cachedSettings: AppSettings
    #endif

    init() {
        #if canImport(GRDB)
        let fileManager = FileManager.default
        let containerURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dbURL = containerURL.appendingPathComponent("shelftrack.sqlite")
        try? fileManager.createDirectory(at: containerURL, withIntermediateDirectories: true)
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode=WAL;")
            try db.execute(sql: "PRAGMA synchronous=NORMAL;")
            try db.execute(sql: "PRAGMA foreign_keys=ON;")
        }
        dbQueue = try! DatabaseQueue(path: dbURL.path, configuration: configuration)
        try? migrator.migrate(dbQueue)
        #else
        let defaults = UserDefaults(suiteName: "com.shelftrack.settings") ?? .standard
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.settingsKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            self.cachedSettings = decoded
        } else {
            self.cachedSettings = .initial
        }
        #endif
    }

    #if canImport(GRDB)
    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_schema") { db in
            try db.create(table: "item") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("sub_name", .text).notNull().defaults(to: "")
                t.column("type", .text).notNull()
                t.column("size_ml", .integer).notNull()
                t.column("quantity", .integer).notNull().defaults(to: 0)
                t.column("minimum", .integer).notNull().defaults(to: 0)
                t.column("primary_location_id", .text)
                t.column("norm_name", .text).notNull()
                t.column("norm_type", .text).notNull()
                t.column("created_at", .integer).notNull()
                t.column("updated_at", .integer).notNull()
                t.foreignKey(["primary_location_id"], references: "location", onDelete: .setNull)
            }

            try db.create(table: "location") { t in
                t.column("id", .text).primaryKey()
                t.column("parent_id", .text).indexed().references("location", onDelete: .cascade)
                t.column("kind", .text).notNull()
                t.column("name", .text).notNull()
                t.column("path", .text).notNull()
            }

            try db.create(table: "item_location") { t in
                t.column("id", .text).primaryKey()
                t.column("item_id", .text).notNull().indexed().references("item", onDelete: .cascade)
                t.column("location_id", .text).notNull().indexed().references("location", onDelete: .cascade)
                t.column("is_primary", .boolean).notNull().defaults(to: false)
            }

            try db.create(index: "idx_item_identity", on: "item", columns: ["norm_name", "size_ml", "norm_type"], unique: false)
            try db.create(index: "idx_item_type", on: "item", columns: ["norm_type"])
            try db.create(index: "idx_item_primary_location", on: "item", columns: ["primary_location_id"])
            try db.create(index: "idx_item_minimum", on: "item", columns: ["minimum", "quantity"])

            try db.create(table: "activity") { t in
                t.column("id", .text).primaryKey()
                t.column("action", .text).notNull()
                t.column("entity", .text).notNull()
                t.column("entity_id", .text)
                t.column("before_json", .text)
                t.column("after_json", .text)
                t.column("meta_json", .text)
                t.column("created_at", .integer).notNull()
            }

            try db.create(table: "search_history") { t in
                t.column("id", .text).primaryKey()
                t.column("query", .text).notNull().unique()
                t.column("last_used_at", .integer).notNull()
            }

            try db.create(table: "settings") { t in
                t.column("id", .integer).primaryKey().defaults(to: 1)
                t.column("pin_hash", .blob)
                t.column("pin_salt", .blob)
                t.column("failed_attempts", .integer).notNull().defaults(to: 0)
                t.column("cooldown_until", .integer)
                t.column("auto_lock_minutes", .integer).notNull().defaults(to: 5)
                t.column("biometrics_enabled", .boolean).notNull().defaults(to: false)
            }

            try db.create(table: "csv_import_staging") { t in
                t.column("id", .integer).primaryKey(autoincrement: true)
                t.column("payload", .blob).notNull()
            }

            try db.create(table: "fts_item") { t in
                t.column("rowid", .integer).primaryKey()
                t.column("display_name", .text)
                t.column("type", .text)
                t.column("size_tokens", .text)
                t.column("location_tokens", .text)
                t.column("norm_name", .text)
                t.column("norm_type", .text)
            }
        }
        return migrator
    }
    #endif

    func loadSettings() -> AppSettings {
        #if canImport(GRDB)
        do {
            if let row = try dbQueue.read({ db -> Row? in
                try Row.fetchOne(db, sql: "SELECT pin_hash, pin_salt, failed_attempts, cooldown_until, auto_lock_minutes, biometrics_enabled FROM settings WHERE id = 1")
            }) {
                let pinHash: Data? = row["pin_hash"]
                let pinSalt: Data? = row["pin_salt"]
                let failedAttempts: Int = row["failed_attempts"]
                let cooldownValue: Int64? = row["cooldown_until"]
                let autoLock: Int = row["auto_lock_minutes"]
                let biometricsFlag: Int = row["biometrics_enabled"]
                return AppSettings(
                    pinHash: pinHash,
                    pinSalt: pinSalt,
                    failedAttempts: failedAttempts,
                    cooldownUntil: cooldownValue.flatMap { Date(timeIntervalSince1970: TimeInterval($0)) },
                    autoLockMinutes: autoLock,
                    biometricsEnabled: biometricsFlag != 0
                )
            } else {
                let initial = AppSettings.initial
                save(settings: initial)
                return initial
            }
        } catch {
            return AppSettings.initial
        }
        #else
        return cachedSettings
        #endif
    }

    func save(settings: AppSettings) {
        #if canImport(GRDB)
        do {
            try dbQueue.write { db in
                let cooldownValue = settings.cooldownUntil.map { Int64($0.timeIntervalSince1970) }
                try db.execute(sql: """
                    INSERT INTO settings (id, pin_hash, pin_salt, failed_attempts, cooldown_until, auto_lock_minutes, biometrics_enabled)
                    VALUES (1, :pin_hash, :pin_salt, :failed_attempts, :cooldown_until, :auto_lock_minutes, :biometrics_enabled)
                    ON CONFLICT(id) DO UPDATE SET
                        pin_hash = excluded.pin_hash,
                        pin_salt = excluded.pin_salt,
                        failed_attempts = excluded.failed_attempts,
                        cooldown_until = excluded.cooldown_until,
                        auto_lock_minutes = excluded.auto_lock_minutes,
                        biometrics_enabled = excluded.biometrics_enabled
                    """,
                                 arguments: [
                                    "pin_hash": settings.pinHash as Data?,
                                    "pin_salt": settings.pinSalt as Data?,
                                    "failed_attempts": settings.failedAttempts,
                                    "cooldown_until": cooldownValue as Int64?,
                                    "auto_lock_minutes": settings.autoLockMinutes,
                                    "biometrics_enabled": settings.biometricsEnabled ? 1 : 0
                                 ])
            }
        } catch {
            // In production we might surface diagnostics; here we silently ignore to keep the app running.
        }
        #else
        cachedSettings = settings
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: Self.settingsKey)
        }
        #endif
    }

    #if !canImport(GRDB)
    func resetForTesting() {
        cachedSettings = .initial
        defaults.removeObject(forKey: Self.settingsKey)
    }
    #else
    func resetForTesting() {
        try? dbQueue.write { db in
            try db.execute(sql: "DELETE FROM settings")
        }
    }
    #endif
}
