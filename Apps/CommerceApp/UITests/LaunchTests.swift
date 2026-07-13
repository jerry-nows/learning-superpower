import XCTest

final class LaunchTests: XCTestCase {
    func testApplicationLaunches() {
        let application = XCUIApplication()

        application.launch()

        XCTAssertEqual(application.state, .runningForeground)
    }
}
