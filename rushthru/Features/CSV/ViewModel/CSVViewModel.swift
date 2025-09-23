import Foundation

@MainActor
final class CSVViewModel: ObservableObject {
    enum CSVError: Error {
        case validationFailed([CSVValidationIssue])
    }

    private let inventoryService: InventoryService
    private let locationCoordinator: LocationsViewModel
    private let activityLogger: ActivityLogViewModel

    @Published private(set) var lastImportSummary: CSVImportSummary?
    @Published private(set) var lastValidationIssues: [CSVValidationIssue] = []

    init(inventoryService: InventoryService, locationCoordinator: LocationsViewModel, activityLogger: ActivityLogViewModel) {
        self.inventoryService = inventoryService
        self.locationCoordinator = locationCoordinator
        self.activityLogger = activityLogger
    }

    func bootstrap() async {}

    func exportInventory() -> String {
        let header = "id,name,sub_name,type,size,quantity,aisle,shelf,row,column"
        let rows = inventoryService.items.map { item in
            "\(item.id.uuidString),\(item.name),\(item.subName),\(item.type),\(item.sizeML),\(item.quantity),\(item.aisle),\(item.shelf),\(item.row),\(item.column)"
        }
        let csv = ([header] + rows).joined(separator: "\n")
        activityLogger.log(action: .export, entity: .system, entityID: nil, before: nil, after: csv)
        return csv
    }

    func validate(csv: String) -> [CSVValidationIssue] {
        var issues: [CSVValidationIssue] = []
        let lines = csv.split(separator: "\n").map(String.init)
        guard !lines.isEmpty else {
            issues.append(CSVValidationIssue(row: nil, column: nil, message: "CSV is empty", kind: .validation))
            lastValidationIssues = issues
            return issues
        }
        let requiredColumns = ["name", "type", "size", "quantity"]
        let headerColumns = lines[0].split(separator: ",").map(String.init)
        for column in requiredColumns where !headerColumns.contains(column) {
            issues.append(CSVValidationIssue(row: 0, column: column, message: "Missing column \(column)", kind: .missingColumn))
        }
        lastValidationIssues = issues
        return issues
    }

    func replaceInventory(with csv: String) async throws {
        lastImportSummary = nil
        let issues = validate(csv: csv)
        guard issues.isEmpty else { throw CSVError.validationFailed(issues) }
        lastValidationIssues = issues
        // Minimal stub that wipes current inventory and re-parses rows.
        let lines = csv.split(separator: "\n").map(String.init)
        guard lines.count > 1 else { return }
        var newItems: [InventoryItem] = []
        let activeStore = inventoryService.ensureActiveStoreID() ?? locationCoordinator.selectedStoreID ?? UUID()
        for (index, line) in lines.enumerated() where index > 0 {
            let values = line.split(separator: ",").map(String.init)
            guard values.count >= 6 else { continue }
            let identifier = UUID(uuidString: values[0]) ?? UUID()
            let name = values[1]
            let subName = values[2]
            let type = values[3].isEmpty ? "Other" : values[3]
            let size = Int(values[4]) ?? 0
            let quantity = Int(values[5]) ?? 0
            let aisle = values.indices.contains(6) ? values[6] : ""
            let shelf = values.indices.contains(7) ? values[7] : ""
            let row = values.indices.contains(8) ? values[8] : ""
            let column = values.indices.contains(9) ? values[9] : ""
            let item = InventoryItem(
                id: identifier,
                name: name,
                subName: subName,
                type: type,
                sizeML: size,
                quantity: quantity,
                storeID: activeStore,
                aisle: aisle,
                shelf: shelf,
                row: row,
                column: column
            )
            newItems.append(item)
        }
        await inventoryService.replaceAll(with: newItems)
        lastImportSummary = CSVImportSummary(importedItems: newItems.count, importedLocations: 0, warnings: [])
        activityLogger.log(action: .import, entity: .batch, entityID: nil, before: nil, after: "Imported \(newItems.count) items")
    }
}
