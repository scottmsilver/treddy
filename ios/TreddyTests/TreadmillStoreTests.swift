import XCTest
@testable import Treddy

private actor MockAPIClient: TreadmillAPIClient {
    var workoutsToReturn: [SavedWorkout] = []
    var historyToReturn: [HistoryEntry] = []
    var programToReturn = ProgramState()
    var userToReturn = UserProfile()
    var hrmStatusToReturn = HrmStatusResponse()

    private(set) var updatedBaseURL: String?
    private(set) var speedValues: [Double] = []
    private(set) var inclineValues: [Double] = []
    private(set) var loadedWorkoutID: String?
    private(set) var loadedHistoryID: String?
    private(set) var scannedHRM = false
    private(set) var selectedHRMAddress: String?
    private(set) var forgotHRM = false

    func setBaseURL(_ url: String) async {
        updatedBaseURL = url
    }

    func setUserToReturn(_ user: UserProfile) async {
        userToReturn = user
    }

    func setHrmStatusToReturn(_ status: HrmStatusResponse) async {
        hrmStatusToReturn = status
    }

    func getWorkouts() async throws -> [SavedWorkout] { workoutsToReturn }
    func getHistory() async throws -> [HistoryEntry] { historyToReturn }
    func getProgram() async throws -> ProgramState { programToReturn }
    func getUser() async throws -> UserProfile { userToReturn }
    func getHrmStatus() async throws -> HrmStatusResponse { hrmStatusToReturn }

    func setSpeed(_ mph: Double) async throws { speedValues.append(mph) }
    func setIncline(_ pct: Double) async throws { inclineValues.append(pct) }
    func quickStart(speed: Double, incline: Double) async throws {}
    func startProgram() async throws {}
    func stopProgram() async throws {}
    func pauseProgram() async throws {}
    func skipInterval() async throws {}
    func reset() async throws {}

    func loadWorkout(id: String) async throws { loadedWorkoutID = id }
    func loadHistory(id: String) async throws { loadedHistoryID = id }
    func resumeHistory(id: String) async throws -> ProgramState { programToReturn }
    func adjustDuration(deltaSeconds: Int) async throws -> ProgramState { programToReturn }

    func scanHrmDevices() async throws { scannedHRM = true }
    func selectHrmDevice(address: String) async throws { selectedHRMAddress = address }
    func forgetHrmDevice() async throws { forgotHRM = true }

    func updateUser(weightLbs: Int?, vestLbs: Int?) async throws -> UserProfile { userToReturn }
    func getConfig() async throws -> AppConfig { AppConfig() }
}

private final class MockWebSocketClient: TreadmillWebSocketClient {
    var onStatus: ((TreadmillStatus) -> Void)?
    var onProgram: ((ProgramState) -> Void)?
    var onSession: ((SessionState) -> Void)?
    var onConnection: ((Bool) -> Void)?
    var onHR: ((HeartRateMessage) -> Void)?
    var onScanResult: ((ScanResultMessage) -> Void)?
    var onConnect: (() -> Void)?
    var onDisconnect: (() -> Void)?

    private(set) var connectedURL: String?
    private(set) var disconnectCount = 0

    func connect(to baseURL: String) {
        connectedURL = baseURL
    }

    func disconnect() {
        disconnectCount += 1
    }
}

@MainActor
final class TreadmillStoreTests: XCTestCase {
    func testAdjustSpeedUpdatesOptimisticStateImmediately() async {
        let api = MockAPIClient()
        let socket = MockWebSocketClient()
        let store = TreadmillStore(api: api, webSocket: socket, serverURL: "https://rpi:8000")

        store.status.emuSpeed = 30

        await store.adjustSpeed(delta: 1)

        XCTAssertEqual(store.status.emuSpeed, 31)
        try? await Task.sleep(for: .milliseconds(250))
        let speedValues = await api.speedValues
        XCTAssertEqual(try XCTUnwrap(speedValues.last), 3.1, accuracy: 0.001)
    }

    func testAdjustInclineUpdatesOptimisticStateImmediately() async {
        let api = MockAPIClient()
        let socket = MockWebSocketClient()
        let store = TreadmillStore(api: api, webSocket: socket, serverURL: "https://rpi:8000")

        store.status.emuIncline = 2.0

        await store.adjustIncline(delta: 0.5)

        XCTAssertEqual(store.status.emuIncline, 2.5)
        try? await Task.sleep(for: .milliseconds(250))
        let inclineValues = await api.inclineValues
        XCTAssertEqual(try XCTUnwrap(inclineValues.last), 2.5, accuracy: 0.001)
    }

    func testFreshStatusEchoDoesNotClobberOptimisticSpeed() async {
        let api = MockAPIClient()
        let socket = MockWebSocketClient()
        let store = TreadmillStore(api: api, webSocket: socket, serverURL: "https://rpi:8000")

        store.status.emuSpeed = 30
        await store.adjustSpeed(delta: 1)

        var echoed = TreadmillStatus()
        echoed.emuSpeed = 12
        echoed.emuIncline = 0
        socket.onStatus?(echoed)

        XCTAssertEqual(store.status.emuSpeed, 31)
    }

    func testProgramRunningRoutesToRunning() {
        let api = MockAPIClient()
        let socket = MockWebSocketClient()
        let store = TreadmillStore(api: api, webSocket: socket, serverURL: "https://rpi:8000")

        XCTAssertEqual(store.currentRoute, .lobby)

        var running = ProgramState()
        running.running = true
        socket.onProgram?(running)

        XCTAssertEqual(store.currentRoute, .running)
    }

    func testLoadAllHydratesUserAndHrmState() async {
        let api = MockAPIClient()
        var user = UserProfile()
        user.id = "1"
        user.weightLbs = 180
        user.vestLbs = 0
        await api.setUserToReturn(user)

        var hrmDevice = HrmDevice()
        hrmDevice.address = "AA"
        hrmDevice.name = "Chest Strap"
        hrmDevice.rssi = -50

        var hrmStatus = HrmStatusResponse()
        hrmStatus.heartRate = 72
        hrmStatus.connected = true
        hrmStatus.device = "Chest Strap"
        hrmStatus.availableDevices = [hrmDevice]
        await api.setHrmStatusToReturn(hrmStatus)

        let socket = MockWebSocketClient()
        let store = TreadmillStore(api: api, webSocket: socket, serverURL: "https://rpi:8000")

        await store.loadAll()

        XCTAssertEqual(store.userProfile.weightLbs, 180)
        XCTAssertEqual(store.hrmDevices.count, 1)
        XCTAssertEqual(store.status.heartRate, 72)
        XCTAssertTrue(store.status.hrmConnected)
    }

    func testScanResultUpdatesVisibleDevices() {
        let api = MockAPIClient()
        let socket = MockWebSocketClient()
        let store = TreadmillStore(api: api, webSocket: socket, serverURL: "https://rpi:8000")

        var device = HrmDevice()
        device.address = "AA"
        device.name = "Chest Strap"
        device.rssi = -42

        var result = ScanResultMessage()
        result.type = "scan_result"
        result.devices = [device]
        socket.onScanResult?(result)

        XCTAssertEqual(store.hrmDevices.count, 1)
        XCTAssertEqual(store.hrmDevices.first?.name, "Chest Strap")
    }
}
