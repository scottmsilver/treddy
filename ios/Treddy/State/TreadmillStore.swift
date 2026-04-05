import Foundation
import os
import SwiftUI

protocol TreadmillAPIClient: Sendable {
    func setBaseURL(_ url: String) async
    func getWorkouts() async throws -> [SavedWorkout]
    func getHistory() async throws -> [HistoryEntry]
    func getProgram() async throws -> ProgramState
    func getUser() async throws -> UserProfile
    func getHrmStatus() async throws -> HrmStatusResponse
    func setSpeed(_ mph: Double) async throws
    func setIncline(_ pct: Double) async throws
    func quickStart(speed: Double, incline: Double) async throws
    func startProgram() async throws
    func stopProgram() async throws
    func pauseProgram() async throws
    func skipInterval() async throws
    func prevInterval() async throws
    func reset() async throws
    func loadWorkout(id: String) async throws
    func loadHistory(id: String) async throws
    func resumeHistory(id: String) async throws -> ProgramState
    func adjustDuration(deltaSeconds: Int) async throws -> ProgramState
    func scanHrmDevices() async throws
    func selectHrmDevice(address: String) async throws
    func forgetHrmDevice() async throws
    func updateUser(weightLbs: Int?, vestLbs: Int?) async throws -> UserProfile
    func getConfig() async throws -> AppConfig
    func getProfiles() async throws -> [Profile]
    func createProfile(name: String, color: String?) async throws -> Profile
    func selectProfile(id: String) async throws
    func startGuest() async throws
    func getActiveProfile() async throws -> ActiveProfileResponse
    func deleteWorkout(id: String) async throws
    func saveWorkoutFromHistory(historyId: String) async throws
}

extension TreadmillAPI: TreadmillAPIClient {
    func setBaseURL(_ url: String) async {
        updateBaseURL(url)
    }
}

/// Single source of truth for all treadmill state.
/// Owns the WebSocket connection, API client, and observable state.
@Observable
@MainActor
final class TreadmillStore {
    private let logger = Logger(subsystem: "com.treddy", category: "Store")
    private let reconcileWindow: TimeInterval = 0.75
    private let debounceDelay: Duration = .milliseconds(150)

    // MARK: - Observable state

    var status = TreadmillStatus()
    var program = ProgramState()
    var session = SessionState()
    var workouts: [SavedWorkout] = []
    var history: [HistoryEntry] = []
    var userProfile = UserProfile()
    var hrmDevices: [HrmDevice] = []
    var profiles: [Profile] = []
    var activeProfile: Profile? = nil
    var guestMode = false
    var setupComplete: Bool = UserDefaults.standard.bool(forKey: "setup_complete") {
        didSet {
            UserDefaults.standard.set(setupComplete, forKey: "setup_complete")
        }
    }
    var currentRoute: AppRoute = UserDefaults.standard.bool(forKey: "setup_complete") ? .profilePicker : .setup
    var isSettingsPresented = false
    var debugUnlocked = false
    var smartassEnabled = UserDefaults.standard.bool(forKey: "smartass_enabled") {
        didSet {
            UserDefaults.standard.set(smartassEnabled, forKey: "smartass_enabled")
        }
    }
    private(set) var voice: VoiceCoordinator?
    var voiceState: VoiceState { voice?.state ?? .idle }
    var isConnected = false
    var toastMessage: String?
    var serverURL: String {
        didSet {
            UserDefaults.standard.set(serverURL, forKey: "server_url")
            reconnect()
        }
    }

    // MARK: - Services

    private(set) var api: any TreadmillAPIClient
    private let ws: any TreadmillWebSocketClient
    private var speedTask: Task<Void, Never>?
    private var inclineTask: Task<Void, Never>?
    private var dirtySpeedAt: Date?
    private var dirtyInclineAt: Date?

    // MARK: - Init

    init(
        api: (any TreadmillAPIClient)? = nil,
        webSocket: (any TreadmillWebSocketClient)? = nil,
        serverURL: String? = nil
    ) {
        let savedURL = serverURL ?? UserDefaults.standard.string(forKey: "server_url") ?? "https://rpi:8000"
        self.serverURL = savedURL
        self.api = api ?? TreadmillAPI(baseURL: savedURL)
        self.ws = webSocket ?? TreadmillWebSocket()

        ws.onStatus = { [weak self] status in self?.handleStatus(status) }
        ws.onProgram = { [weak self] program in self?.handleProgram(program) }
        ws.onSession = { [weak self] session in self?.session = session }
        ws.onConnection = { [weak self] connected in self?.isConnected = connected }
        ws.onHR = { [weak self] hr in self?.handleHeartRate(hr) }
        ws.onScanResult = { [weak self] scan in self?.hrmDevices = scan.devices }
        ws.onProfileChanged = { [weak self] msg in self?.handleProfileChanged(msg) }
        ws.onConnect = { [weak self] in
            self?.isConnected = true
            // Configure remote logger for voice debugging
            if let url = self?.serverURL {
                RemoteLogger.shared.configure(baseURL: url)
            }
            // Lazily create voice coordinator on first connect
            if self?.voice == nil, let s = self {
                s.voice = VoiceCoordinator(store: s)
            }
            self?.voice?.ensureConnected()
            Task { await self?.loadAll() }
        }
        ws.onDisconnect = { [weak self] in
            self?.isConnected = false
            self?.voice?.onServerDisconnected()
        }

        ws.connect(to: savedURL)
    }

    // MARK: - Data loading

    func loadData() async {
        await loadAll()
    }

    func loadAll() async {
        await syncActiveProfile()
        await refreshUserProfile()
        do {
            async let w = api.getWorkouts()
            async let h = api.getHistory()
            async let p = api.getProgram()
            workouts = try await w
            history = try await h
            program = try await p
            // Only auto-navigate TO running (not away from it) on data load
            if program.running {
                currentRoute = .running
            }
        } catch {
            logger.error("Failed to load program data: \(error)")
        }
    }

    func reconnectIfNeeded() {
        guard !isConnected else { return }
        reconnect()
    }

    func reconnect() {
        speedTask?.cancel()
        inclineTask?.cancel()
        ws.disconnect()
        Task {
            await api.setBaseURL(serverURL)
        }
        ws.connect(to: serverURL)
    }

    // MARK: - Actions

    func presentSettings() {
        isSettingsPresented = true
    }

    func navigate(to route: AppRoute) {
        currentRoute = route
    }

    func completeSetup() {
        setupComplete = true
        currentRoute = .profilePicker
    }

    func unlockDebug() {
        debugUnlocked = true
    }

    func toggleVoice(prompt: String? = nil) {
        voice?.toggle(prompt: prompt)
    }

    func showToast(_ message: String) {
        toastMessage = message
        Task {
            try? await Task.sleep(for: .seconds(3))
            if toastMessage == message {
                toastMessage = nil
            }
        }
    }

    func refreshUserProfile() async {
        do {
            async let user = api.getUser()
            async let hrm = api.getHrmStatus()
            userProfile = try await user
            let hrmStatus = try await hrm
            hrmDevices = hrmStatus.availableDevices
            status.heartRate = hrmStatus.heartRate
            status.hrmConnected = hrmStatus.connected
            status.hrmDevice = hrmStatus.device
        } catch {
            logger.error("Failed to refresh user profile: \(error)")
        }
    }

    func setSpeed(_ mph: Double) async {
        let clamped = max(0, min(12.0, mph))
        dirtySpeedAt = .now
        status.emuSpeed = Int((clamped * 10).rounded())
        enqueueSpeedSend(clamped)
    }

    func setIncline(_ pct: Double) async {
        let clamped = max(0, min(15.0, pct))
        dirtyInclineAt = .now
        status.emuIncline = clamped
        enqueueInclineSend(clamped)
    }

    func adjustSpeed(delta: Int) async {
        let newTenths = max(0, min(120, status.emuSpeed + delta))
        dirtySpeedAt = .now
        status.emuSpeed = newTenths
        enqueueSpeedSend(Double(newTenths) / 10.0)
    }

    func adjustIncline(delta: Double) async {
        let rawIncline = status.emuIncline + delta
        let newIncline = min(15.0, max(0.0, (rawIncline * 2).rounded() / 2))
        dirtyInclineAt = .now
        status.emuIncline = newIncline
        enqueueInclineSend(newIncline)
    }

    func quickStart(speed: Double = 3.0, incline: Double = 0) async {
        do {
            try await api.quickStart(speed: speed, incline: incline)
            program = try await api.getProgram()
            currentRoute = .running
        } catch {
            logger.error("Failed to quick start: \(error)")
        }
    }

    func startProgram() async {
        do {
            try await api.startProgram()
            program = try await api.getProgram()
            currentRoute = .running
        } catch {
            logger.error("Failed to start program: \(error)")
        }
    }

    func stop() async {
        try? await api.stopProgram()
    }

    func pause() async {
        try? await api.pauseProgram()
    }

    func skip() async {
        try? await api.skipInterval()
    }

    func prev() async {
        try? await api.prevInterval()
    }

    func adjustDuration(_ seconds: Int) async {
        do {
            program = try await api.adjustDuration(deltaSeconds: seconds)
        } catch {
            logger.error("Failed to adjust duration: \(error)")
        }
    }

    func resetSession() async {
        try? await api.stopProgram() // save run record via _apply_stop()
        try? await api.reset()
        await loadAll()
    }

    func loadWorkout(_ id: String) async {
        do {
            try await api.loadWorkout(id: id)
            try await api.startProgram()
            currentRoute = .running
            await loadAll()
        } catch {
            logger.error("Failed to load workout: \(error)")
        }
    }

    func deleteWorkout(_ id: String) async {
        do {
            try await api.deleteWorkout(id: id)
            workouts.removeAll { $0.id == id }
        } catch {
            logger.error("Failed to delete workout: \(error)")
        }
    }

    func toggleSaveHistory(_ entry: HistoryEntry) async {
        if entry.saved, let workoutId = entry.savedWorkoutId {
            // Unsave by exact ID from server
            await deleteWorkout(workoutId)
            if let idx = history.firstIndex(where: { $0.id == entry.id }) {
                history[idx].saved = false
                history[idx].savedWorkoutId = nil
            }
        } else if !entry.saved {
            // Save
            do {
                try await api.saveWorkoutFromHistory(historyId: entry.id)
                // Reload to get the new saved_workout_id
                history = (try? await api.getHistory()) ?? history
                workouts = (try? await api.getWorkouts()) ?? workouts
            } catch {
                logger.error("Failed to save workout: \(error)")
            }
        }
    }

    func loadHistoryEntry(_ id: String) async {
        do {
            try await api.loadHistory(id: id)
            try await api.startProgram()
            currentRoute = .running
            await loadAll()
        } catch {
            logger.error("Failed to load history: \(error)")
        }
    }

    func resumeHistoryEntry(_ id: String) async {
        do {
            program = try await api.resumeHistory(id: id)
            currentRoute = .running
            await loadAll()
        } catch {
            logger.error("Failed to resume history: \(error)")
        }
    }

    func scanHrmDevices() async {
        do {
            try await api.scanHrmDevices()
        } catch {
            logger.error("Failed to scan HRM devices: \(error)")
        }
    }

    func selectHrmDevice(_ device: HrmDevice) async {
        do {
            try await api.selectHrmDevice(address: device.address)
        } catch {
            logger.error("Failed to select HRM device: \(error)")
        }
    }

    func forgetHrmDevice() async {
        do {
            try await api.forgetHrmDevice()
            status.hrmConnected = false
            status.hrmDevice = ""
        } catch {
            logger.error("Failed to forget HRM device: \(error)")
        }
    }

    // MARK: - Profiles

    func fetchProfiles() async {
        do {
            profiles = try await api.getProfiles()
        } catch {
            logger.error("Failed to fetch profiles: \(error)")
        }
    }

    func selectProfile(_ id: String) async {
        // Stop any active session first — server rejects profile switch during sessions
        if session.active || program.running {
            try? await api.stopProgram()
            try? await api.reset()
        }
        do {
            try await api.selectProfile(id: id)
            await loadAll()
        } catch {
            logger.error("Failed to select profile: \(error)")
            showToast("Could not switch profile")
        }
    }

    func startGuestMode() async {
        if session.active || program.running {
            try? await api.stopProgram()
            try? await api.reset()
        }
        do {
            try await api.startGuest()
            await loadAll()
        } catch {
            logger.error("Failed to start guest mode: \(error)")
            showToast("Could not switch to guest")
        }
    }

    func createProfile(name: String, color: String?) async -> Profile? {
        do {
            let profile = try await api.createProfile(name: name, color: color)
            profiles.append(profile)
            return profile
        } catch {
            logger.error("Failed to create profile: \(error)")
            return nil
        }
    }

    func syncActiveProfile() async {
        do {
            let resp = try await api.getActiveProfile()
            activeProfile = resp.profile
            guestMode = resp.guestMode
        } catch {
            logger.error("Failed to sync active profile: \(error)")
        }
    }

    private func handleProfileChanged(_ msg: ProfileChangedMessage) {
        activeProfile = msg.profile
        guestMode = msg.guestMode
        // Reload profile-scoped data (workouts, history)
        Task { await loadAll() }
    }

    private func enqueueSpeedSend(_ mph: Double) {
        speedTask?.cancel()
        speedTask = Task { [api, debounceDelay] in
            try? await Task.sleep(for: debounceDelay)
            try? await api.setSpeed(mph)
        }
    }

    private func enqueueInclineSend(_ incline: Double) {
        inclineTask?.cancel()
        inclineTask = Task { [api, debounceDelay] in
            try? await Task.sleep(for: debounceDelay)
            try? await api.setIncline(incline)
        }
    }

    private func handleStatus(_ incoming: TreadmillStatus) {
        if !isConnected { isConnected = true }
        let now = Date()
        let keepSpeed = dirtySpeedAt.map { now.timeIntervalSince($0) < reconcileWindow } ?? false
        let keepIncline = dirtyInclineAt.map { now.timeIntervalSince($0) < reconcileWindow } ?? false

        status.proxy = incoming.proxy
        status.emulate = incoming.emulate
        status.emuSpeed = keepSpeed ? status.emuSpeed : incoming.emuSpeed
        status.emuIncline = keepIncline ? status.emuIncline : incoming.emuIncline
        status.speed = incoming.speed
        status.incline = incoming.incline
        status.treadmillConnected = incoming.treadmillConnected
        status.heartRate = incoming.heartRate
        status.hrmConnected = incoming.hrmConnected
        status.hrmDevice = incoming.hrmDevice
    }

    private func handleProgram(_ incoming: ProgramState) {
        let wasRunning = program.running
        program = incoming
        // Only auto-navigate to running on START (transition from not-running to running)
        // Don't force-navigate if user has deliberately navigated elsewhere
        if program.running && !wasRunning {
            currentRoute = .running
        }
    }

    private func handleHeartRate(_ hr: HeartRateMessage) {
        status.heartRate = hr.bpm
        status.hrmConnected = hr.connected
        status.hrmDevice = hr.device
    }
}
