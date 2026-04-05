import Foundation

/// Fire-and-forget logger that POSTs to /api/device-log on the treadmill server.
/// Useful for debugging iPad without Xcode console access.
final class RemoteLogger: @unchecked Sendable {
    static let shared = RemoteLogger()

    private var baseURL: String?
    private let session: URLSession
    private let queue = DispatchQueue(label: "com.treddy.remotelog", qos: .utility)

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 3
        session = URLSession(configuration: config, delegate: TrustAllDelegate(), delegateQueue: nil)
    }

    func configure(baseURL: String) {
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    func send(_ message: String, category: String = "ios") {
        guard let base = baseURL,
              let url = URL(string: "\(base)/api/device-log") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = ["category": category, "message": message]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        queue.async { [weak self] in
            self?.session.dataTask(with: request) { _, _, _ in }.resume()
        }
    }
}
