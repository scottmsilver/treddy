import Foundation

/// REST client for the treadmill server. All tool execution goes through /api/tool.
actor TreadmillAPI {
    private let session: URLSession
    private var baseURL: String

    private struct APIErrorEnvelope: Decodable {
        var ok: Bool?
        var error: String?
    }

    private lazy var decoder: JSONDecoder = {
        let d = JSONDecoder()
        // Per-field CodingKeys handle snake_case (not blanket conversion)
        return d
    }()

    init(baseURL: String) {
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        self.session = URLSession(configuration: config, delegate: TrustAllDelegate(), delegateQueue: nil)
    }

    init(baseURL: String, session: URLSession) {
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.session = session
    }

    func updateBaseURL(_ url: String) {
        self.baseURL = url.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    // MARK: - Generic helpers

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, httpResponse)
    }

    private func errorMessage(from data: Data) -> String? {
        guard let envelope = try? decoder.decode(APIErrorEnvelope.self, from: data) else {
            return nil
        }
        return envelope.error
    }

    private func ensureSuccess(data: Data, response: HTTPURLResponse) throws {
        guard (200..<300).contains(response.statusCode) else {
            throw TreadmillAPIError.server(errorMessage(from: data) ?? "HTTP \(response.statusCode)")
        }
        if let envelope = try? decoder.decode(APIErrorEnvelope.self, from: data), envelope.ok == false {
            throw TreadmillAPIError.server(envelope.error ?? "Request failed")
        }
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let url = URL(string: "\(baseURL)\(path)")!
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        try ensureSuccess(data: data, response: httpResponse)
        return try decoder.decode(T.self, from: data)
    }

    private func post<T: Decodable>(_ path: String, body: [String: Any]? = nil) async throws -> T {
        var request = URLRequest(url: URL(string: "\(baseURL)\(path)")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body = body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await perform(request)
        try ensureSuccess(data: data, response: response)
        return try decoder.decode(T.self, from: data)
    }

    private func put<T: Decodable>(_ path: String, body: [String: Any]? = nil) async throws -> T {
        var request = URLRequest(url: URL(string: "\(baseURL)\(path)")!)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body = body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await perform(request)
        try ensureSuccess(data: data, response: response)
        return try decoder.decode(T.self, from: data)
    }

    private func postRaw(_ path: String, body: [String: Any]? = nil) async throws {
        var request = URLRequest(url: URL(string: "\(baseURL)\(path)")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body = body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await perform(request)
        try ensureSuccess(data: data, response: response)
    }

    // MARK: - Status & Config

    func getStatus() async throws -> TreadmillStatus {
        try await get("/api/status")
    }

    func getConfig() async throws -> AppConfig {
        try await get("/api/config")
    }

    func getUser() async throws -> UserProfile {
        try await get("/api/user")
    }

    @discardableResult
    func updateUser(weightLbs: Int? = nil, vestLbs: Int? = nil) async throws -> UserProfile {
        if vestLbs != nil {
            throw TreadmillAPIError.unsupported("vest_lbs is not supported by /api/user")
        }
        var body: [String: Any] = [:]
        if let w = weightLbs { body["weight_lbs"] = w }
        return try await put("/api/user", body: body)
    }

    // MARK: - Workouts & History

    func getWorkouts() async throws -> [SavedWorkout] {
        try await get("/api/workouts")
    }

    func getHistory() async throws -> [HistoryEntry] {
        try await get("/api/programs/history")
    }

    func getProgram() async throws -> ProgramState {
        try await get("/api/program")
    }

    func loadWorkout(id: String) async throws {
        try await postRaw("/api/workouts/\(id)/load")
    }

    func deleteWorkout(id: String) async throws {
        var request = URLRequest(url: URL(string: "\(baseURL)/api/workouts/\(id)")!)
        request.httpMethod = "DELETE"
        let (data, response) = try await perform(request)
        try ensureSuccess(data: data, response: response)
    }

    func loadHistory(id: String) async throws {
        try await postRaw("/api/programs/history/\(id)/load")
    }

    func resumeHistory(id: String) async throws -> ProgramState {
        return try await post("/api/programs/history/\(id)/resume")
    }

    // MARK: - Control

    func setSpeed(_ mph: Double) async throws {
        try await postRaw("/api/speed", body: ["value": mph])
    }

    func setIncline(_ pct: Double) async throws {
        try await postRaw("/api/incline", body: ["value": pct])
    }

    func quickStart(speed: Double, incline: Double) async throws {
        try await postRaw("/api/program/quick-start", body: ["speed": speed, "incline": incline])
    }

    func startProgram() async throws {
        try await postRaw("/api/program/start")
    }

    func stopProgram() async throws {
        try await postRaw("/api/program/stop")
    }

    func pauseProgram() async throws {
        try await postRaw("/api/program/pause")
    }

    func skipInterval() async throws {
        try await postRaw("/api/program/skip")
    }

    func prevInterval() async throws {
        try await postRaw("/api/program/prev")
    }

    func reset() async throws {
        try await postRaw("/api/reset")
    }

    // MARK: - HRM

    func getHrmStatus() async throws -> HrmStatusResponse {
        try await get("/api/hrm")
    }

    func scanHrmDevices() async throws {
        try await postRaw("/api/hrm/scan")
    }

    func selectHrmDevice(address: String) async throws {
        try await postRaw("/api/hrm/select", body: ["address": address])
    }

    func forgetHrmDevice() async throws {
        try await postRaw("/api/hrm/forget")
    }

    func adjustDuration(deltaSeconds: Int) async throws -> ProgramState {
        return try await post("/api/program/adjust-duration", body: ["delta_seconds": deltaSeconds])
    }

    // MARK: - Profiles

    func getProfiles() async throws -> [Profile] {
        try await get("/api/profiles")
    }

    func createProfile(name: String, color: String? = nil) async throws -> Profile {
        var body: [String: Any] = ["name": name]
        if let c = color { body["color"] = c }
        struct Wrapper: Codable {
            var profile: Profile
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                profile = try c.decode(Profile.self, forKey: .profile)
            }
        }
        let resp: Wrapper = try await post("/api/profiles", body: body)
        return resp.profile
    }

    func selectProfile(id: String) async throws {
        try await postRaw("/api/profile/select", body: ["id": id])
    }

    func startGuest() async throws {
        try await postRaw("/api/profile/guest")
    }

    func getActiveProfile() async throws -> ActiveProfileResponse {
        try await get("/api/profile/active")
    }

    // MARK: - Generic tool execution (Postel's Law: single path for all tools)

    func execTool(name: String, args: [String: Any], context: String? = nil) async throws -> ToolCallResponse {
        var body: [String: Any] = ["name": name, "args": args]
        if let ctx = context { body["context"] = ctx }
        return try await post("/api/tool", body: body)
    }

    // MARK: - Chat

    struct ChatResponse: Codable {
        var text: String = ""
    }

    func sendChat(_ message: String) async throws -> ChatResponse {
        try await post("/api/chat", body: ["message": message])
    }
}

enum TreadmillAPIError: LocalizedError {
    case server(String)
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .server(let message):
            return message
        case .unsupported(let message):
            return message
        }
    }
}
