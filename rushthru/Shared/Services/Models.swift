import Foundation

struct InventoryItem: Identifiable, Equatable, Hashable, Codable {
    enum ItemType: String, CaseIterable, Codable, Hashable {
        case whiskey, tequila, vodka, gin, rum, beer, wine, liqueur, cider, sake, other

        var displayName: String {
            rawValue.capitalized
        }
    }

    var id: UUID
    var name: String
    var subName: String
    var type: ItemType
    var sizeML: Int
    var quantity: Int
    var minimum: Int
    var primaryLocationID: UUID?
    var storeID: UUID
    var createdAt: Date
    var updatedAt: Date

    var isBelowMinimum: Bool { quantity < minimum }

    init(
        id: UUID = UUID(),
        name: String,
        subName: String = "",
        type: ItemType,
        sizeML: Int,
        quantity: Int,
        minimum: Int = 0,
        primaryLocationID: UUID? = nil,
        storeID: UUID,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.subName = subName
        self.type = type
        self.sizeML = sizeML
        self.quantity = quantity
        self.minimum = minimum
        self.primaryLocationID = primaryLocationID
        self.storeID = storeID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var displayName: String {
        if subName.isEmpty {
            return name
        } else {
            return "\(name) — \(subName)"
        }
    }

    var normalizedIdentity: ItemIdentity {
        ItemIdentity(name: name, type: type, sizeML: sizeML)
    }
}

struct ItemIdentity: Hashable, Codable {
    var normalizedName: String
    var normalizedType: InventoryItem.ItemType
    var normalizedSizeML: Int

    init(name: String, type: InventoryItem.ItemType, sizeML: Int) {
        self.normalizedName = ItemIdentity.normalize(name)
        self.normalizedType = type
        self.normalizedSizeML = sizeML
    }

    static func normalize(_ name: String) -> String {
        name.folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

struct LocationNode: Identifiable, Hashable, Codable {
    enum Kind: String, CaseIterable, Codable {
        case store, aisle, row, shelf, bin

        var displayName: String {
            rawValue.capitalized
        }
    }

    var id: UUID
    var parentID: UUID?
    var kind: Kind
    var name: String
    var path: String

    init(id: UUID = UUID(), parentID: UUID?, kind: Kind, name: String, path: String) {
        self.id = id
        self.parentID = parentID
        self.kind = kind
        self.name = name
        self.path = path
    }
}

struct ItemLocation: Identifiable, Hashable, Codable {
    var id: UUID
    var itemID: UUID
    var locationID: UUID
    var isPrimary: Bool

    init(id: UUID = UUID(), itemID: UUID, locationID: UUID, isPrimary: Bool) {
        self.id = id
        self.itemID = itemID
        self.locationID = locationID
        self.isPrimary = isPrimary
    }
}

struct ActivityLogEntry: Identifiable, Hashable, Codable {
    enum Action: String, Codable, CaseIterable {
        case create, edit, merge, refill, count, `import`, export
    }

    enum Entity: String, Codable, CaseIterable {
        case item, location, batch, system
    }

    var id: UUID
    var action: Action
    var entity: Entity
    var entityID: UUID?
    var beforeJSON: String?
    var afterJSON: String?
    var metadataJSON: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        action: Action,
        entity: Entity,
        entityID: UUID?,
        beforeJSON: String?,
        afterJSON: String?,
        metadataJSON: String?,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.action = action
        self.entity = entity
        self.entityID = entityID
        self.beforeJSON = beforeJSON
        self.afterJSON = afterJSON
        self.metadataJSON = metadataJSON
        self.createdAt = createdAt
    }
}

struct SearchHistoryEntry: Identifiable, Hashable, Codable {
    var id: UUID
    var query: String
    var lastUsedAt: Date

    init(id: UUID = UUID(), query: String, lastUsedAt: Date = Date()) {
        self.id = id
        self.query = query
        self.lastUsedAt = lastUsedAt
    }
}

struct AppSettings: Codable, Equatable {
    var pinHash: Data?
    var pinSalt: Data?
    var failedAttempts: Int
    var cooldownUntil: Date?
    var autoLockMinutes: Int
    var biometricsEnabled: Bool

    static let initial = AppSettings(
        pinHash: nil,
        pinSalt: nil,
        failedAttempts: 0,
        cooldownUntil: nil,
        autoLockMinutes: 5,
        biometricsEnabled: false
    )
}

struct CSVValidationIssue: Identifiable, Hashable {
    enum IssueKind: String {
        case missingColumn
        case invalidValue
        case duplicateIdentifier
        case validation
    }

    var id = UUID()
    var row: Int?
    var column: String?
    var message: String
    var kind: IssueKind
}

struct CSVImportSummary: Hashable {
    var importedItems: Int
    var importedLocations: Int
    var warnings: [CSVValidationIssue]
}

struct OCRCandidateField: Hashable {
    enum FieldType: CaseIterable {
        case name, subName, type, sizeML
    }

    var type: FieldType
    var value: String
    var confidence: Double
}

struct OCRResult {
    var fields: [OCRCandidateField]
    var imageIdentifier: UUID = UUID()

    static let empty = OCRResult(fields: [])
}
