import Foundation
import Combine

@MainActor
final class AppEnvironment: ObservableObject {
    @MainActor
    struct Dependencies {
        let database: DatabaseManager
        let auth: AuthService
        let inventory: InventoryService
        let refill: RefillViewModel
        let search: SearchViewModel
        let locations: LocationsViewModel
        let csv: CSVViewModel
        let activity: ActivityLogViewModel
        let capture: CaptureViewModel
        let bulkCounts: BulkCountViewModel

        static func standard() -> Dependencies {
            let database = DatabaseManager.shared
            let authService = AuthService(database: database)
            let activityLogger = ActivityLogViewModel()
            let locationCoordinator = LocationsViewModel(activityLogger: activityLogger)
            let inventoryService = InventoryService(activityLogger: activityLogger, locationCoordinator: locationCoordinator)

            #if canImport(Vision)
            let shelfRecognizer: ShelfRecognizing = DinoV3ShelfRecognizer()
            #else
            let shelfRecognizer: ShelfRecognizing = NullShelfRecognizer()
            #endif
            let refillViewModel = RefillViewModel(inventoryService: inventoryService, shelfRecognizer: shelfRecognizer)
            let searchViewModel = SearchViewModel(inventoryService: inventoryService)
            let csvViewModel = CSVViewModel(
                inventoryService: inventoryService,
                locationCoordinator: locationCoordinator,
                activityLogger: activityLogger
            )

            #if canImport(Vision)
            let cameraRecognizer: DonutTextRecognizing = DonutSmallTextRecognizer()
            #else
            let cameraRecognizer: DonutTextRecognizing = NullDonutTextRecognizer()
            #endif
            let galleryRecognizer: DonutTextRecognizing = MLKitTextRecognizerAdapter(fallback: cameraRecognizer)
            let captureViewModel = CaptureViewModel(
                inventoryService: inventoryService,
                cameraRecognizer: cameraRecognizer,
                galleryRecognizer: galleryRecognizer
            )
            let bulkCountsViewModel = BulkCountViewModel(inventoryService: inventoryService)

            return Dependencies(
                database: database,
                auth: authService,
                inventory: inventoryService,
                refill: refillViewModel,
                search: searchViewModel,
                locations: locationCoordinator,
                csv: csvViewModel,
                activity: activityLogger,
                capture: captureViewModel,
                bulkCounts: bulkCountsViewModel
            )
        }
    }

    let database: DatabaseManager
    let auth: AuthService
    let inventory: InventoryService
    let refill: RefillViewModel
    let search: SearchViewModel
    let locations: LocationsViewModel
    let csv: CSVViewModel
    let activity: ActivityLogViewModel
    let capture: CaptureViewModel
    let bulkCounts: BulkCountViewModel

    @Published private(set) var isReady = false

    init(preview: Bool = false, dependencies: Dependencies = .standard()) {
        self.database = dependencies.database
        self.auth = dependencies.auth
        self.inventory = dependencies.inventory
        self.refill = dependencies.refill
        self.search = dependencies.search
        self.locations = dependencies.locations
        self.csv = dependencies.csv
        self.activity = dependencies.activity
        self.capture = dependencies.capture
        self.bulkCounts = dependencies.bulkCounts

        if preview {
            Task {
                await seedPreviewData()
            }
        }
    }

    func start() async {
        guard !isReady else { return }
        await auth.bootstrap()
        await locations.bootstrap()
        await inventory.bootstrap()
        await activity.bootstrap()
        await csv.bootstrap()
        await search.bootstrap()
        isReady = true
    }

    private func seedPreviewData() async {
        let location = LocationNode(parentID: nil, kind: .store, name: "Main Store", path: "Main Store")
        await locations.upsert(location: location)
        locations.selectedStoreID = location.id
        let bourbon = InventoryItem(name: "Trailhead Bourbon", subName: "Single Barrel", type: "Whiskey", sizeML: 750, quantity: 6, minimum: 4, primaryLocationID: location.id, storeID: location.id, aisle: "Aisle 1", shelf: "Shelf 1", row: "Row 1", column: "Column 1")
        await inventory.create(item: bourbon)
        let tequila = InventoryItem(name: "Azure Agave", subName: "Reposado", type: "Tequila", sizeML: 750, quantity: 3, minimum: 6, primaryLocationID: location.id, storeID: location.id, aisle: "Aisle 2", shelf: "Shelf 1", row: "Row 2", column: "Column 3")
        await inventory.create(item: tequila)
        await search.bootstrap()
    }
}
