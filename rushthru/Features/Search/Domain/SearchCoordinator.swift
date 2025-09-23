import Foundation
import Combine

@MainActor
final class SearchCoordinator: ObservableObject {
    @Published private(set) var results: [InventoryItem] = []
    @Published private(set) var history: [SearchHistoryEntry] = []
    @Published var query: String = "" {
        didSet { performSearch() }
    }
    @Published var selectedType: String? {
        didSet { performSearch() }
    }
    @Published var selectedSize: Int? {
        didSet { performSearch() }
    }

    private let inventoryService: InventoryService
    private let defaults: UserDefaults
    private let historyKey = "search.recent"
    private var cancellables = Set<AnyCancellable>()

    init(inventoryService: InventoryService, defaults: UserDefaults = .standard) {
        self.inventoryService = inventoryService
        self.defaults = defaults
        inventoryService.$items
            .sink { [weak self] _ in self?.performSearch() }
            .store(in: &cancellables)
        loadHistory()
    }

    func bootstrap() async {
        performSearch()
    }

    func performSearch() {
        let tokens = query.lowercased().split(separator: " ")
        var items = inventoryService.items
        if let type = selectedType, !type.isEmpty {
            let normalized = ItemIdentity.normalizeType(type)
            items = items.filter { ItemIdentity.normalizeType($0.type) == normalized }
        }
        if let size = selectedSize {
            items = items.filter { $0.sizeML == size }
        }
        if !tokens.isEmpty {
            items = items.filter { item in
                let haystack = "\(item.name.lowercased()) \(item.subName.lowercased()) \(item.type.lowercased()) \(item.sizeML) \(item.aisle.lowercased()) \(item.shelf.lowercased()) \(item.row.lowercased()) \(item.column.lowercased())"
                return tokens.allSatisfy { haystack.contains($0) }
            }
        }
        results = items.sorted { $0.name < $1.name }
    }

    func selectSuggestion(_ suggestion: String) {
        query = suggestion
        addToHistory(suggestion)
        performSearch()
    }

    func addToHistory(_ query: String) {
        guard !query.isEmpty else { return }
        var updated = history
        if let index = updated.firstIndex(where: { $0.query.caseInsensitiveCompare(query) == .orderedSame }) {
            updated[index].lastUsedAt = Date()
        } else {
            updated.insert(SearchHistoryEntry(query: query), at: 0)
        }
        updated.sort { $0.lastUsedAt > $1.lastUsedAt }
        updated = Array(updated.prefix(10))
        history = updated
        persistHistory()
    }

    func clearHistory() {
        history = []
        persistHistory()
    }

    private func loadHistory() {
        guard let data = defaults.data(forKey: historyKey) else { return }
        let decoder = JSONDecoder()
        if let saved = try? decoder.decode([SearchHistoryEntry].self, from: data) {
            history = saved.sorted { $0.lastUsedAt > $1.lastUsedAt }
        }
    }

    private func persistHistory() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(history) {
            defaults.set(data, forKey: historyKey)
        }
    }
}
