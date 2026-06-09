import XCTest
import CoreData
@testable import JournalingCompanion

final class PersistenceControllerTests: XCTestCase {
    func testInMemoryStoreLoadsWithoutError() {
        let controller = PersistenceController(inMemory: true)
        XCTAssertNotNil(controller.container.viewContext)
    }

    func testSessionCanBeSavedAndFetched() throws {
        let controller = PersistenceController(inMemory: true)
        let ctx = controller.container.viewContext

        let session = CDSession(context: ctx)
        session.id = UUID()
        session.startedAt = Date()
        try ctx.save()

        let request: NSFetchRequest<CDSession> = CDSession.fetchRequest()
        let results = try ctx.fetch(request)
        XCTAssertEqual(results.count, 1)
    }
}
