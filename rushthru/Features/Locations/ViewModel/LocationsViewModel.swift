import Foundation

@MainActor
final class LocationsViewModel: ObservableObject {
    @Published private(set) var locations: [LocationNode] = []
    @Published var selectedStoreID: UUID? {
        didSet {
            guard !isRestoringState, oldValue != selectedStoreID else { return }
            schedulePersist()
        }
    }
    private let activityLogger: ActivityLogViewModel
    private let stateURL: URL
    private var pendingSaveTask: Task<Void, Never>?
    private var saveGeneration: UInt64 = 0
    private var isRestoringState = false
    private var needsInitialPersist = false
    let aisleOptions: [String]
    let shelfOptions: [String]
    let rowOptions: [String]
    let columnOptions: [String]

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init(activityLogger: ActivityLogViewModel) {
        self.activityLogger = activityLogger
        let fileManager = FileManager.default
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directoryURL = baseURL.appendingPathComponent("Locations", isDirectory: true)
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        self.stateURL = directoryURL.appendingPathComponent("locations-state.json")
        self.aisleOptions = (1...12).map { "Aisle \($0)" }
        self.shelfOptions = (1...10).map { "Shelf \($0)" }
        self.rowOptions = (1...10).map { "Row \($0)" }
        self.columnOptions = (1...10).map { "Column \($0)" }
        isRestoringState = true
        loadPersistedState()
        isRestoringState = false
        if needsInitialPersist {
            needsInitialPersist = false
            schedulePersist()
        }
    }

    func bootstrap() async {
        if locations.isEmpty {
            let root = LocationNode(parentID: nil, kind: .store, name: "Store", path: "Store")
            locations.append(root)
            selectedStoreID = root.id
            schedulePersist()
        } else if selectedStoreID == nil {
            selectedStoreID = stores.first?.id
        }
    }

    func upsert(location: LocationNode) async {
        if let index = locations.firstIndex(where: { $0.id == location.id }) {
            locations[index] = location
            activityLogger.log(action: .edit, entity: .location, entityID: location.id, before: nil, after: nil)
        } else {
            locations.append(location)
            activityLogger.log(action: .create, entity: .location, entityID: location.id, before: nil, after: nil)
            if location.kind == .store, selectedStoreID == nil {
                selectedStoreID = location.id
            }
        }
        schedulePersist()
    }

    func delete(locationID: UUID) async {
        locations.removeAll { $0.id == locationID }
        activityLogger.log(action: .edit, entity: .location, entityID: locationID, before: nil, after: nil)
        if selectedStoreID == locationID {
            selectedStoreID = stores.first?.id
        }
        schedulePersist()
    }

    func location(for id: UUID?) -> LocationNode? {
        guard let id else { return nil }
        return locations.first { $0.id == id }
    }

    func storeName(for id: UUID?) -> String? {
        location(for: id)?.name
    }

    @discardableResult
    func createStore(named name: String) async -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if stores.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) { return false }
        let node = LocationNode(parentID: nil, kind: .store, name: trimmed, path: trimmed)
        await upsert(location: node)
        return true
    }

    var stores: [LocationNode] {
        locations.filter { $0.kind == .store }
    }

    func clearAll() {
        locations.removeAll()
        selectedStoreID = nil
        activityLogger.log(action: .edit, entity: .location, entityID: nil, before: nil, after: "Cleared all locations")
        schedulePersist()
    }

    private func schedulePersist() {
        let state = PersistedLocationsState(locations: locations, selectedStoreID: selectedStoreID)
        let url = stateURL
        saveGeneration &+= 1
        let generation = saveGeneration
        pendingSaveTask?.cancel()
        pendingSaveTask = Task.detached(priority: .utility) { [weak self, state, url, generation] in
            guard let self else { return }
            do {
                try Task.checkCancellation()
                let data = try LocationsViewModel.encoder.encode(state)
                try Task.checkCancellation()
                let directory = url.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let isLatest = await MainActor.run { generation == self.saveGeneration }
                guard isLatest else { return }
                try Task.checkCancellation()
                try data.write(to: url, options: .atomic)
            } catch is CancellationError {
                return
            } catch {
                #if DEBUG
                print("Locations persistence error: \(error)")
                #endif
            }
        }
    }

    private func loadPersistedState() {
        guard let data = try? Data(contentsOf: stateURL) else { return }
        do {
            let state = try Self.decoder.decode(PersistedLocationsState.self, from: data)
            locations = state.locations
            if let storedSelection = state.selectedStoreID,
               locations.contains(where: { $0.id == storedSelection }) {
                selectedStoreID = storedSelection
            } else {
                let fallback = locations.first?.id
                selectedStoreID = fallback
                if fallback != state.selectedStoreID {
                    needsInitialPersist = true
                }
            }
        } catch {
            #if DEBUG
            print("Failed to load locations: \(error)")
            #endif
        }
    }
}

private struct PersistedLocationsState: Codable {
    var locations: [LocationNode]
    var selectedStoreID: UUID?
}
