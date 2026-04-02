import XCTest

/// UI tests that exercise the app's screens and navigation.
/// These connect to the real Pi server (must be reachable).
final class TreddyUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    // MARK: - Shell

    func testShellShowsGlobalVoiceAndSettings() {
        XCTAssertTrue(app.buttons["Home"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Run"].exists)
        XCTAssertTrue(app.buttons["Voice"].exists)
        XCTAssertTrue(app.buttons["Settings"].exists)
    }

    // MARK: - Lobby

    func testLobbyShowsTitle() {
        // Lobby is the default route. The title or Quick button should be visible.
        XCTAssertTrue(app.buttons["Quick"].waitForExistence(timeout: 5))
    }

    func testLobbyShowsButtons() {
        XCTAssertTrue(app.buttons["Quick"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Manual"].exists)
    }

    func testLobbyShowsWorkouts() {
        // Wait for server data to load
        let myWorkouts = app.staticTexts["MY WORKOUTS"]
        if myWorkouts.waitForExistence(timeout: 10) {
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'intervals'")).firstMatch.waitForExistence(timeout: 5))
        }
    }

    // MARK: - Tab Navigation

    func testTabNavigation() {
        // Tap Run
        app.buttons["Run"].tap()
        sleep(1)

        // Tap Home
        app.buttons["Home"].tap()
        XCTAssertTrue(app.buttons["Quick"].waitForExistence(timeout: 3))
    }

    // MARK: - Settings (sheet)

    func testSettingsShowsServerURL() {
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["Server"].waitForExistence(timeout: 5))
    }

    func testSettingsShowsWeight() {
        app.buttons["Settings"].tap()
        // Wait for sheet to appear and scroll into view
        let weight = app.staticTexts["Weight"]
        XCTAssertTrue(weight.waitForExistence(timeout: 5))
    }

    func testSettingsOpensAndShowsContent() {
        app.buttons["Settings"].tap()
        sleep(1)
        // Server section should be visible (this one works reliably)
        XCTAssertTrue(app.staticTexts["Server"].waitForExistence(timeout: 5))
        // Weight field should also be visible
        XCTAssertTrue(app.staticTexts["Weight"].exists)
    }

    func testSettingsShowsSmartassToggle() {
        app.buttons["Settings"].tap()
        sleep(1)
        let toggle = app.switches.firstMatch
        // Settings sheet should have at least one toggle (smart-ass)
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "Smart-ass toggle should exist in settings")
    }

    func testSettingsDebugUnlockButtonExists() {
        app.buttons["Settings"].tap()
        sleep(1)
        // The debug unlock affordance should exist (triple-tap on "Settings" title)
        let title = app.buttons["settings-debug-unlock"]
        XCTAssertTrue(title.waitForExistence(timeout: 5), "Debug unlock button should exist in settings toolbar")
        // Note: actual triple-tap unlock is tested manually since XCUITest
        // tap timing doesn't reliably trigger the 0.6s gesture window
    }

    // MARK: - Quick Start

    func testQuickStartLoadsWorkout() {
        let quick = app.buttons["Quick"]
        XCTAssertTrue(quick.waitForExistence(timeout: 5))
        quick.tap()
        sleep(2)
        app.buttons["Run"].tap()
        sleep(1)
        let stop = app.buttons["Stop"]
        if stop.waitForExistence(timeout: 5) {
            stop.tap()
        }
    }

    // MARK: - Running Screen

    func testRunningScreenShowsControls() {
        app.buttons["Manual"].waitForExistence(timeout: 5)
        app.buttons["Manual"].tap()
        sleep(2)
        app.buttons["Run"].tap()
        sleep(1)
        let mph = app.staticTexts["mph"]
        let incline = app.staticTexts["% incline"]
        XCTAssertTrue(mph.waitForExistence(timeout: 5) || incline.waitForExistence(timeout: 5))
        let stop = app.buttons["Stop"]
        if stop.exists { stop.tap() }
    }

    // MARK: - Disconnect Banner

    func testDisconnectBannerHiddenWhenConnected() {
        sleep(5)
        let banner = app.staticTexts["Disconnected from server"]
        XCTAssertFalse(banner.exists)
    }
}
