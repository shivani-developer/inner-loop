import XCTest
@testable import JournalingCompanion

final class AppBrandTests: XCTestCase {
    func testPublicBrandingUsesInnerLoop() {
        XCTAssertEqual(AppBrand.displayName, "InnerLoop")
        XCTAssertEqual(AppBrand.subtitle, "On-device Socratic reflection")
    }
}
