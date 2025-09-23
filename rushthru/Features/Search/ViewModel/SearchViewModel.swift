import Foundation
import Combine

@MainActor
final class SearchViewModel: ObservableObject {
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
    private let maxHistoryCount = 10
    private static let historyEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private static let historyDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

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
        let normalizedType = selectedType.map(ItemIdentity.normalizeType)
        let sizeFilter = selectedSize
        let tokens = query
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)

        let sequence = inventoryService.items.lazy.filter { item in
            if let normalizedType, ItemIdentity.normalizeType(item.type) != normalizedType {
                return false
            }
            if let sizeFilter, item.sizeML != sizeFilter {
                return false
            }
            guard !tokens.isEmpty else { return true }
            let haystack = "\(item.name.lowercased()) \(item.subName.lowercased()) \(item.type.lowercased()) \(item.sizeML) \(item.aisle.lowercased()) \(item.shelf.lowercased()) \(item.row.lowercased()) \(item.column.lowercased())"
            return tokens.allSatisfy { haystack.contains($0) }
        }
        results = sequence.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
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
        if updated.count > maxHistoryCount {
            updated = Array(updated.prefix(maxHistoryCount))
        }
        history = updated
        persistHistory()
    }

    func clearHistory() {
        history = []
        persistHistory()
    }

    func clearAll() {
        history = []
        results = []
        query = ""
        selectedType = nil
        selectedSize = nil
        persistHistory()
    }

    private func loadHistory() {
        guard let data = defaults.data(forKey: historyKey) else { return }
        if let saved = try? Self.historyDecoder.decode([SearchHistoryEntry].self, from: data) {
            history = saved.sorted { $0.lastUsedAt > $1.lastUsedAt }
        }
    }

    private func persistHistory() {
        if let data = try? Self.historyEncoder.encode(history) {
            defaults.set(data, forKey: historyKey)
        }
    }
}
