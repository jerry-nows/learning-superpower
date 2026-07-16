import Foundation
import XCTest

/// End-to-end login checks for the local stack.
///
/// Credentials are intentionally read only from the test runner environment.
/// Without an explicitly configured endpoint and seeded user these tests skip,
/// so a normal simulator test run never attempts an accidental network call.
final class LoginFlowTests: XCTestCase {
    private let endpointKey = "UI_TEST_API_BASE_URL"
    private let emailKey = "SEED_USER_EMAIL"
    private let passwordKey = "SEED_USER_PASSWORD"

    func testInvalidLoginShowsAccessibleError() throws {
        let configuration = try configuration()
        let application = makeApplication(configuration)
        application.launch()

        let email = application.textFields["Email address"]
        let password = application.secureTextFields["Password"]
        XCTAssertTrue(email.waitForExistence(timeout: 5))
        XCTAssertTrue(password.exists)

        email.tap()
        email.typeText(configuration.email)
        password.tap()
        password.typeText(configuration.password + "-invalid")
        application.buttons["Sign in"].tap()

        let error = application.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "email or password")
        ).firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 10), "Invalid-login error must be accessible")
    }

    func testValidLoginShowsProductsRoot() throws {
        let configuration = try configuration()
        let application = makeApplication(configuration)
        application.launch()

        let email = application.textFields["Email address"]
        let password = application.secureTextFields["Password"]
        XCTAssertTrue(email.waitForExistence(timeout: 5))
        XCTAssertTrue(password.exists)

        email.tap()
        email.typeText(configuration.email)
        password.tap()
        password.typeText(configuration.password)
        application.buttons["Sign in"].tap()

        XCTAssertTrue(application.navigationBars["Products"].waitForExistence(timeout: 15))
    }

    private struct Configuration {
        let endpoint: String
        let email: String
        let password: String
    }

    private func configuration() throws -> Configuration {
        let environment = ProcessInfo.processInfo.environment
        guard environment["UI_TEST_OFFLINE"] != "1" else {
            throw XCTSkip("UI_TEST_OFFLINE=1; network-dependent UI tests are disabled")
        }
        guard let endpoint = environment[endpointKey],
              let url = URL(string: endpoint),
              ["http", "https"].contains(url.scheme?.lowercased()),
              let email = environment[emailKey], !email.isEmpty,
              let password = environment[passwordKey], !password.isEmpty else {
            throw XCTSkip("Set UI_TEST_API_BASE_URL, SEED_USER_EMAIL and SEED_USER_PASSWORD")
        }
        return Configuration(endpoint: endpoint, email: email, password: password)
    }

    private func makeApplication(_ configuration: Configuration) -> XCUIApplication {
        let application = XCUIApplication()
        application.launchEnvironment["API_BASE_URL"] = configuration.endpoint
        application.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        return application
    }
}
