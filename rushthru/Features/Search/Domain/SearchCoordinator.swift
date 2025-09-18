import Foundation
import Combine

@MainActor
final class SearchCoordinator: ObservableObject {
    @Published private(set) var results: [InventoryItem] = []
    @Published private(set) var history: [SearchHistoryEntry] = []
    @Published var query: String = "" {
        didSet { performSearch() }
    }
    @Published var selectedType: InventoryItem.ItemType? {
        didSet { performSearch() }
    }

    private let inventoryService: InventoryService
    private var cancellables = Set<AnyCancellable>()

    init(inventoryService: InventoryService) {
        self.inventoryService = inventoryService
        inventoryService.$items
            .sink { [weak self] _ in self?.performSearch() }
            .store(in: &cancellables)
    }

    func bootstrap() async {
        performSearch()
    }

    func performSearch() {
        let tokens = query.lowercased().split(separator: " ")
        var items = inventoryService.items
        if let type = selectedType {
            items = items.filter { $0.type == type }
        }
        if !tokens.isEmpty {
            items = items.filter { item in
                let haystack = "\(item.name.lowercased()) \(item.subName.lowercased()) \(item.type.rawValue) \(item.sizeML)"
                return tokens.allSatisfy { haystack.contains($0) }
            }
        }
        results = items.sorted { $0.name < $1.name }
    }

    func selectSuggestion(_ suggestion: String) {
        query = suggestion
        performSearch()
    }

    func addToHistory(_ query: String) {
        guard !query.isEmpty else { return }
        if let index = history.firstIndex(where: { $0.query.caseInsensitiveCompare(query) == .orderedSame }) {
            history[index].lastUsedAt = Date()
        } else {
            history.insert(SearchHistoryEntry(query: query), at: 0)
        }
        history.sort { $0.lastUsedAt > $1.lastUsedAt }
        history = Array(history.prefix(10))
    }
}
