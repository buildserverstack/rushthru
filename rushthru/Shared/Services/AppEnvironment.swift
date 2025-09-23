import Foundation
import Combine

@MainActor
final class AppEnvironment: ObservableObject {
    let database: DatabaseManager
    let auth: AuthService
    let inventory: InventoryService
    let refill: RefillService
    let search: SearchCoordinator
    let locations: LocationCoordinator
    let csv: CSVCoordinator
    let activity: ActivityLogCoordinator
    let capture: CaptureCoordinator
    let bulkCounts: BulkCountCoordinator

    @Published private(set) var isReady = false

    init(preview: Bool = false) {
        self.database = DatabaseManager.shared
        let activityLogger = ActivityLogCoordinator()
        let locationCoordinator = LocationCoordinator(activityLogger: activityLogger)
        let inventoryService = InventoryService(activityLogger: activityLogger, locationCoordinator: locationCoordinator)
        self.inventory = inventoryService
        self.locations = locationCoordinator
        self.activity = activityLogger

        #if canImport(Vision)
        let shelfRecognizer: ShelfRecognizing = DinoV3ShelfRecognizer()
        #else
        let shelfRecognizer: ShelfRecognizing = NullShelfRecognizer()
        #endif
        self.refill = RefillService(inventoryService: inventoryService, shelfRecognizer: shelfRecognizer)
        self.search = SearchCoordinator(inventoryService: inventoryService)
        self.csv = CSVCoordinator(inventoryService: inventoryService, locationCoordinator: locationCoordinator, activityLogger: activityLogger)
        #if canImport(Vision)
        let cameraRecognizer: DonutTextRecognizing = DonutSmallTextRecognizer()
        #else
        let cameraRecognizer: DonutTextRecognizing = NullDonutTextRecognizer()
        #endif
        let galleryRecognizer: DonutTextRecognizing = MLKitTextRecognizerAdapter(fallback: cameraRecognizer)
        self.capture = CaptureCoordinator(
            inventoryService: inventoryService,
            cameraRecognizer: cameraRecognizer,
            galleryRecognizer: galleryRecognizer
        )
        self.bulkCounts = BulkCountCoordinator(inventoryService: inventoryService)
        self.auth = AuthService()

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
