import XCTest
@testable import BouncerCore

final class CycleTests: XCTestCase {
    func testCibleSuivanteEnAvant() {
        let apps = ["a", "b", "c"]
        XCTAssertEqual(prochaineCible(dans: apps, depuis: "a", forward: true), "b")
    }
}
