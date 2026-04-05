import Foundation
import os

enum VoiceState: String, Sendable {
    case idle, connecting, listening, speaking
}

protocol GeminiLiveCallbacks: AnyObject, Sendable {
    func onStateChange(_ state: VoiceState)
    func onSpeakingStart()
    func onSpeakingEnd()
    func onInterrupted()
    func onTextFallback(_ text: String, executedTools: [String])
    func onError(_ error: Error)
}

/// Bidirectional WebSocket client for Gemini Live voice.
final class GeminiLiveClient: @unchecked Sendable {
    private let logger = Logger(subsystem: "com.treddy", category: "GeminiLive")
    private let messageQueue = DispatchQueue(label: "com.treddy.gemini.messages")

    private let apiKey: String
    private let model: String
    private let voice: String
    private let functionBridge: FunctionBridge
    private let serverTools: [[String: Any]]?
    private let serverPrompt: String?

    weak var callbacks: GeminiLiveCallbacks?
    var stateContext: String = ""

    private var ws: URLSessionWebSocketTask?
    private var session: URLSession?
    private var setupDone = false
    private var turnTextParts: [String] = []
    private var turnToolCalls: [String] = []
    private var receivingAudio = false
    private var lastAudioSentMs: Int64 = 0

    private var isV31: Bool { model.contains("3.1") }

    var isConnected: Bool { setupDone && ws != nil }

    init(
        apiKey: String,
        model: String,
        voice: String,
        functionBridge: FunctionBridge,
        serverTools: [[String: Any]]? = nil,
        serverPrompt: String? = nil
    ) {
        self.apiKey = apiKey
        self.model = model.isEmpty ? "gemini-3.1-flash-live-preview" : model
        self.voice = voice.isEmpty ? "Kore" : voice
        self.functionBridge = functionBridge
        self.serverTools = serverTools
        self.serverPrompt = serverPrompt
    }

    func connect() {
        let urlString = "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContentConstrained?access_token=\(apiKey)"
        guard let url = URL(string: urlString) else {
            logger.error("Invalid WebSocket URL")
            return
        }

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = .infinity
        session = URLSession(configuration: config)
        ws = session?.webSocketTask(with: url)
        ws?.resume()
        logger.info("Connecting to Gemini Live (model=\(self.model))")

        sendSetup()
        receiveLoop()
    }

    func disconnect() {
        ws?.cancel(with: .normalClosure, reason: nil)
        ws = nil
        session = nil
        setupDone = false
        callbacks?.onStateChange(.idle)
    }

    // MARK: - Send

    func sendAudio(_ base64: String) {
        messageQueue.async { [self] in
            guard setupDone else { return }
            lastAudioSentMs = Int64(Date().timeIntervalSince1970 * 1000)

            let msg: [String: Any]
            if isV31 {
                msg = ["realtimeInput": ["audio": ["mimeType": "audio/pcm;rate=16000", "data": base64]]]
            } else {
                msg = ["realtimeInput": ["mediaChunks": [["mimeType": "audio/pcm;rate=16000", "data": base64]]]]
            }
            sendJSON(msg)
        }
    }

    func sendTextPrompt(_ text: String) {
        guard setupDone else { return }
        if isV31 {
            sendJSON(["realtimeInput": ["text": text]])
        } else {
            sendJSON(["client_content": [
                "turns": [["role": "user", "parts": [["text": text]]]],
                "turn_complete": true
            ]])
        }
    }

    func sendStateUpdate(_ context: String) {
        guard setupDone else { return }
        let text = "[State update — do not respond]\n\(context)"
        sendTextPrompt(text)
    }

    // MARK: - Setup

    private func sendSetup() {
        let prompt = (serverPrompt ?? "") + "\n\nCurrent treadmill state:\n\(stateContext)"

        var setup: [String: Any] = [
            "model": "models/\(model)",
            "system_instruction": ["parts": [["text": prompt]]],
            "generation_config": [
                "speech_config": ["voice_config": ["prebuilt_voice_config": ["voice_name": voice]]],
                "response_modalities": ["AUDIO"],
                "thinking_config": ["thinking_level": "minimal"]
            ],
            "realtime_input_config": [
                "automatic_activity_detection": [
                    "end_of_speech_sensitivity": "END_SENSITIVITY_HIGH",
                    "silence_duration_ms": 100
                ]
            ]
        ]

        if let tools = serverTools {
            setup["tools"] = tools
        }

        sendJSON(["setup": setup])
    }

    // MARK: - Receive

    private func receiveLoop() {
        ws?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let message):
                self.messageQueue.async {
                    self.handleMessage(message)
                }
                self.receiveLoop()
            case .failure(let error):
                self.logger.error("WebSocket error: \(error)")
                self.callbacks?.onError(error)
                self.callbacks?.onStateChange(.idle)
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            guard let data = text.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            processJSON(json)
        case .data(let data):
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            processJSON(json)
        @unknown default:
            break
        }
    }

    private func processJSON(_ msg: [String: Any]) {
        // Setup complete
        if msg["setupComplete"] != nil || msg["setup_complete"] != nil {
            setupDone = true
            logger.info("Setup complete, ready for audio")
            callbacks?.onStateChange(.listening)
            return
        }

        // Tool call cancellation
        if msg["toolCallCancellation"] != nil || msg["tool_call_cancellation"] != nil {
            return
        }

        // Tool call
        if let toolCall = (msg["toolCall"] ?? msg["tool_call"]) as? [String: Any],
           let calls = toolCall["functionCalls"] as? [[String: Any]] {
            for fc in calls {
                guard let name = fc["name"] as? String else { continue }
                let fcId = fc["id"] as? String
                let args = fc["args"] as? [String: Any] ?? [:]
                turnToolCalls.append(name)
                logger.info("toolCall: \(name)(\(args))")

                let context = turnTextParts.isEmpty ? nil : turnTextParts.joined(separator: " ")
                let argsData = (try? JSONSerialization.data(withJSONObject: args)) ?? Data()
                Task {
                    let result = await self.functionBridge.execute(name: name, argsJSON: argsData, context: context)
                    self.sendToolResponse(name: result.name, response: result.response, id: fcId)
                }
            }
            if !turnTextParts.isEmpty {
                let text = turnTextParts.joined(separator: " ")
                callbacks?.onTextFallback(text, executedTools: turnToolCalls)
                turnTextParts.removeAll()
            }
            return
        }

        // Server content
        guard let content = (msg["serverContent"] ?? msg["server_content"]) as? [String: Any] else { return }

        // Turn complete
        if content["turnComplete"] != nil || content["turn_complete"] != nil {
            receivingAudio = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.callbacks?.onSpeakingEnd()
            }
            if !turnTextParts.isEmpty {
                let text = turnTextParts.joined(separator: " ")
                callbacks?.onTextFallback(text, executedTools: turnToolCalls)
            }
            turnTextParts.removeAll()
            turnToolCalls.removeAll()
            return
        }

        // Interrupted (barge-in)
        if content["interrupted"] != nil {
            receivingAudio = false
            callbacks?.onInterrupted()
            turnTextParts.removeAll()
            turnToolCalls.removeAll()
            return
        }

        // Model turn with parts
        guard let modelTurn = (content["modelTurn"] ?? content["model_turn"]) as? [String: Any],
              let parts = modelTurn["parts"] as? [[String: Any]] else { return }

        for part in parts {
            // Audio response
            if let inlineData = (part["inlineData"] ?? part["inline_data"]) as? [String: Any],
               let base64 = inlineData["data"] as? String {
                if !receivingAudio {
                    receivingAudio = true
                    callbacks?.onSpeakingStart()
                }
                NotificationCenter.default.post(
                    name: .geminiAudioChunk,
                    object: nil,
                    userInfo: ["data": base64]
                )
            }

            // Text response (fallback)
            if let text = part["text"] as? String {
                turnTextParts.append(text)
            }
        }
    }

    // MARK: - Tool Response

    private func sendToolResponse(name: String, response: String, id: String?) {
        var funcResponse: [String: Any] = [
            "name": name,
            "response": ["result": response]
        ]
        if let id = id { funcResponse["id"] = id }
        sendJSON(["toolResponse": ["functionResponses": [funcResponse]]])
    }

    // MARK: - Helpers

    private func sendJSON(_ obj: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let text = String(data: data, encoding: .utf8) else { return }
        ws?.send(.string(text)) { [weak self] error in
            if let error = error {
                self?.logger.error("Send error: \(error)")
            }
        }
    }
}

extension Notification.Name {
    static let geminiAudioChunk = Notification.Name("geminiAudioChunk")
}
