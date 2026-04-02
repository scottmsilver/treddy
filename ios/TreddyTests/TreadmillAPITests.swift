import XCTest
@testable import Treddy

private final class RequestRecorderURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            fatalError("Missing request handler")
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class RequestRecorder {
    private(set) var lastRequest: URLRequest?
    let session: URLSession

    init(responseJSON: String = "{}", statusCode: Int = 200) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RequestRecorderURLProtocol.self]
        self.session = URLSession(configuration: configuration)

        RequestRecorderURLProtocol.requestHandler = { [weak self] request in
            self?.lastRequest = request
            let url = request.url ?? URL(string: "https://example.invalid")!
            let response = HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(responseJSON.utf8))
        }
    }
}

private func bodyJSON(_ request: URLRequest) -> [String: Any] {
    let data: Data?
    if let httpBody = request.httpBody {
        data = httpBody
    } else if let stream = request.httpBodyStream {
        stream.open()
        defer { stream.close() }
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        var body = Data()
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            body.append(buffer, count: read)
        }
        data = body
    } else {
        data = nil
    }
    guard let data else { return [:] }
    let object = try? JSONSerialization.jsonObject(with: data)
    return object as? [String: Any] ?? [:]
}

private func assertAsyncThrows(
    _ expectedSubstring: String,
    _ operation: @escaping () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await operation()
        XCTFail("Expected error", file: file, line: line)
    } catch {
        XCTAssertTrue(String(describing: error).contains(expectedSubstring), "Unexpected error: \(error)", file: file, line: line)
    }
}

final class TreadmillAPITests: XCTestCase {

    func testUpdateUserUsesPut() async throws {
        let recorder = RequestRecorder(responseJSON: #"{"id":"1","weight_lbs":180,"vest_lbs":20}"#)
        let api = TreadmillAPI(baseURL: "https://rpi:8000", session: recorder.session)

        _ = try await api.updateUser(weightLbs: 180)

        XCTAssertEqual(recorder.lastRequest?.httpMethod, "PUT")
        XCTAssertEqual(recorder.lastRequest?.url?.path, "/api/user")
        XCTAssertEqual(bodyJSON(recorder.lastRequest ?? URLRequest(url: URL(string: "https://example.invalid")!)).keys.sorted(), ["weight_lbs"])
    }

    func testUpdateUserThrowsWhenVestLbsProvided() async {
        let recorder = RequestRecorder(responseJSON: #"{"id":"1","weight_lbs":180}"#)
        let api = TreadmillAPI(baseURL: "https://rpi:8000", session: recorder.session)

        await assertAsyncThrows("vest") {
            _ = try await api.updateUser(weightLbs: 180, vestLbs: 20)
        }
    }

    func testGetHrmStatusUsesGet() async throws {
        let recorder = RequestRecorder(responseJSON: #"{"heart_rate":72,"connected":true,"device":"Chest Strap","available_devices":[]}"#)
        let api = TreadmillAPI(baseURL: "https://rpi:8000", session: recorder.session)

        _ = try await api.getHrmStatus()

        XCTAssertEqual(recorder.lastRequest?.httpMethod, "GET")
        XCTAssertEqual(recorder.lastRequest?.url?.path, "/api/hrm")
    }

    func testScanHrmDevicesUsesPost() async throws {
        let recorder = RequestRecorder(responseJSON: #"{"ok":true}"#)
        let api = TreadmillAPI(baseURL: "https://rpi:8000", session: recorder.session)

        try await api.scanHrmDevices()

        XCTAssertEqual(recorder.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(recorder.lastRequest?.url?.path, "/api/hrm/scan")
    }

    func testSelectHrmDeviceUsesPost() async throws {
        let recorder = RequestRecorder(responseJSON: #"{"ok":true}"#)
        let api = TreadmillAPI(baseURL: "https://rpi:8000", session: recorder.session)

        try await api.selectHrmDevice(address: "AA:BB:CC:DD:EE:FF")

        XCTAssertEqual(recorder.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(recorder.lastRequest?.url?.path, "/api/hrm/select")
    }

    func testForgetHrmDeviceUsesPost() async throws {
        let recorder = RequestRecorder(responseJSON: #"{"ok":true}"#)
        let api = TreadmillAPI(baseURL: "https://rpi:8000", session: recorder.session)

        try await api.forgetHrmDevice()

        XCTAssertEqual(recorder.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(recorder.lastRequest?.url?.path, "/api/hrm/forget")
    }

    func testResumeHistoryUsesPost() async throws {
        let recorder = RequestRecorder(responseJSON: #"{"ok":true,"program":{"name":"Manual","manual":true,"intervals":[]},"running":true,"paused":false,"completed":false,"current_interval":0,"interval_elapsed":0,"total_elapsed":0,"total_duration":0}"#)
        let api = TreadmillAPI(baseURL: "https://rpi:8000", session: recorder.session)

        _ = try await api.resumeHistory(id: "abc123")

        XCTAssertEqual(recorder.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(recorder.lastRequest?.url?.path, "/api/programs/history/abc123/resume")
    }

    func testAdjustDurationUsesPost() async throws {
        let recorder = RequestRecorder(responseJSON: #"{"program":{"name":"Manual","manual":true,"intervals":[]},"running":true,"paused":false,"completed":false,"current_interval":0,"interval_elapsed":0,"total_elapsed":0,"total_duration":120}"#)
        let api = TreadmillAPI(baseURL: "https://rpi:8000", session: recorder.session)

        _ = try await api.adjustDuration(deltaSeconds: 60)

        XCTAssertEqual(recorder.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(recorder.lastRequest?.url?.path, "/api/program/adjust-duration")
    }

    func testScanHrmDevicesThrowsOn503Error() async {
        let recorder = RequestRecorder(responseJSON: #"{"error":"hrm-daemon not connected"}"#, statusCode: 503)
        let api = TreadmillAPI(baseURL: "https://rpi:8000", session: recorder.session)

        await assertAsyncThrows("hrm-daemon not connected") {
            try await api.scanHrmDevices()
        }
    }

    func testSelectHrmDeviceThrowsOn503Error() async {
        let recorder = RequestRecorder(responseJSON: #"{"error":"hrm-daemon not connected"}"#, statusCode: 503)
        let api = TreadmillAPI(baseURL: "https://rpi:8000", session: recorder.session)

        await assertAsyncThrows("hrm-daemon not connected") {
            try await api.selectHrmDevice(address: "AA:BB:CC:DD:EE:FF")
        }
    }

    func testForgetHrmDeviceThrowsOn503Error() async {
        let recorder = RequestRecorder(responseJSON: #"{"error":"hrm-daemon not connected"}"#, statusCode: 503)
        let api = TreadmillAPI(baseURL: "https://rpi:8000", session: recorder.session)

        await assertAsyncThrows("hrm-daemon not connected") {
            try await api.forgetHrmDevice()
        }
    }

    func testResumeHistoryThrowsOnServerError() async {
        let recorder = RequestRecorder(responseJSON: #"{"ok":false,"error":"Program already completed — use load to start over"}"#)
        let api = TreadmillAPI(baseURL: "https://rpi:8000", session: recorder.session)

        await assertAsyncThrows("Program already completed") {
            _ = try await api.resumeHistory(id: "abc123")
        }
    }

    func testAdjustDurationThrowsOnServerError() async {
        let recorder = RequestRecorder(responseJSON: #"{"ok":false,"error":"No manual program running"}"#)
        let api = TreadmillAPI(baseURL: "https://rpi:8000", session: recorder.session)

        await assertAsyncThrows("No manual program running") {
            _ = try await api.adjustDuration(deltaSeconds: 60)
        }
    }
}
