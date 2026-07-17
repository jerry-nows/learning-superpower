import XCTest

final class LaunchTests: XCTestCase {
    func testNetworkFailureCanRecoverWithRetry() {
        let application = XCUIApplication()
        application.launchArguments = ["-ui-test-scenario", "networkFailure"]

        application.launch()

        XCTAssertTrue(application.staticTexts["network-error-message"].waitForExistence(timeout: 5))
        let retry = application.buttons["retry-connection"]
        XCTAssertTrue(retry.exists)
        retry.tap()
        XCTAssertTrue(application.staticTexts["connection-restored-message"].waitForExistence(timeout: 5))
    }

    func testApplicationLaunches() {
        let application = XCUIApplication()

        application.launch()

        XCTAssertEqual(application.state, .runningForeground)
    }
}
