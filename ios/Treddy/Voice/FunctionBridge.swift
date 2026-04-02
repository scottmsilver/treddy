import Foundation

/// Forwards all Gemini tool calls to /api/tool. No client-side tool logic.
actor FunctionBridge {
    private let api: TreadmillAPI

    init(api: TreadmillAPI) {
        self.api = api
    }

    struct Result {
        let name: String
        let response: String
    }

    /// Execute a tool call. Args are pre-serialized to avoid Sendable issues with [String: Any].
    func execute(name: String, argsJSON: Data, context: String? = nil) async -> Result {
        do {
            let args = (try? JSONSerialization.jsonObject(with: argsJSON)) as? [String: Any] ?? [:]
            let resp = try await api.execTool(name: name, args: args, context: context)
            let text = resp.ok ? (resp.result ?? "Done") : "Error: \(resp.error ?? "unknown")"
            return Result(name: name, response: text)
        } catch {
            return Result(name: name, response: "Error: \(error.localizedDescription)")
        }
    }
}
