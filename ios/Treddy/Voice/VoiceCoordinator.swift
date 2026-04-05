import AVFoundation
import os

/// Coordinates voice state, mic capture, audio playback, and Gemini Live connection.
/// Equivalent to Android's VoiceViewModel.
@Observable
@MainActor
final class VoiceCoordinator: GeminiLiveCallbacks {
    private let logger = Logger(subsystem: "com.treddy", category: "VoiceCoordinator")

    private(set) var state: VoiceState = .idle

    private var client: GeminiLiveClient?
    private let capture = AudioCapture()
    private let player = AudioPlayer()
    private var functionBridge: FunctionBridge?
    private var config: AppConfig?
    private var audioObserver: Any?
    private weak var store: TreadmillStore?

    init(store: TreadmillStore) {
        self.store = store
    }

    // MARK: - Public

    /// Called when server WebSocket connects. Starts background Gemini connection.
    func ensureConnected() {
        guard client == nil || !client!.isConnected else { return }
        connectBackground()
    }

    /// Called when server WebSocket disconnects.
    func onServerDisconnected() {
        tearDown()
    }

    /// Toggle voice on/off.
    func toggle(prompt: String? = nil) {
        switch state {
        case .idle:
            if let client = client, client.isConnected {
                if let prompt = prompt {
                    client.sendTextPrompt(prompt)
                }
                startMicCapture()
                state = .listening
            } else {
                state = .connecting
                connectBackground()
            }
        case .connecting:
            state = .idle
            stopMicCapture()
        case .listening, .speaking:
            stopMicCapture()
            player.flush()
            state = .idle
        }
    }

    /// Update Gemini with current treadmill state.
    func updateStateContext(_ context: String) {
        client?.stateContext = context
        if state == .listening || state == .speaking {
            client?.sendStateUpdate(context)
        }
    }

    func tearDown() {
        stopMicCapture()
        client?.disconnect()
        client = nil
        player.tearDown()
        capture.tearDown()
        if let obs = audioObserver {
            NotificationCenter.default.removeObserver(obs)
            audioObserver = nil
        }
        state = .idle
    }

    // MARK: - Background Connection

    private func connectBackground() {
        Task {
            guard let store = store else { return }

            if config == nil {
                config = try? await store.api.getConfig()
            }
            guard let cfg = config, !cfg.geminiApiKey.isEmpty else {
                logger.warning("No Gemini API key")
                state = .idle
                return
            }

            // Create function bridge on first connect
            if functionBridge == nil, let concreteAPI = store.api as? TreadmillAPI {
                functionBridge = FunctionBridge(api: concreteAPI)
            }
            guard let bridge = functionBridge else {
                logger.error("Cannot create FunctionBridge")
                state = .idle
                return
            }

            // Pre-warm audio off the main thread (AudioUnit creation can be slow)
            await Task.detached {
                self.capture.warmUp()
                if let sharedEngine = self.capture.engine {
                    self.player.setup(sharedEngine: sharedEngine)
                } else {
                    self.player.setup()
                }
            }.value

            // Listen for audio chunks from Gemini
            if audioObserver == nil {
                audioObserver = NotificationCenter.default.addObserver(
                    forName: .geminiAudioChunk,
                    object: nil,
                    queue: .main
                ) { [weak self] notification in
                    if let base64 = notification.userInfo?["data"] as? String {
                        self?.player.enqueue(base64)
                    }
                }
            }

            // Serialize tools to plain dict array for Gemini setup
            var toolsArray: [[String: Any]]? = nil
            if let tools = cfg.tools {
                let encoded = try? JSONEncoder().encode(tools)
                if let data = encoded {
                    toolsArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
                }
            }

            let newClient = GeminiLiveClient(
                apiKey: cfg.geminiApiKey,
                model: cfg.geminiLiveModel,
                voice: cfg.geminiVoice,
                functionBridge: bridge,
                serverTools: toolsArray,
                serverPrompt: cfg.systemPrompt
            )
            newClient.callbacks = self
            client = newClient
            newClient.connect()
        }
    }

    // MARK: - Mic

    private var audioChunkCount = 0

    private func startMicCapture() {
        audioChunkCount = 0
        capture.onAudioChunk = { [weak self] base64 in
            self?.client?.sendAudio(base64)
        }
        if !capture.start() {
            logger.error("Failed to start mic")
            state = .idle
        }
    }

    private func stopMicCapture() {
        capture.stop()
    }

    // MARK: - GeminiLiveCallbacks

    nonisolated func onStateChange(_ newState: VoiceState) {
        Task { @MainActor in
            if newState == .listening && self.state == .connecting {
                self.state = .listening
                self.startMicCapture()
            }
        }
    }

    nonisolated func onSpeakingStart() {
        Task { @MainActor in
            self.state = .speaking
        }
    }

    nonisolated func onSpeakingEnd() {
        Task { @MainActor in
            self.player.drain()
            if self.state == .speaking {
                self.state = .listening
            }
        }
    }

    nonisolated func onInterrupted() {
        Task { @MainActor in
            self.player.flush()
            self.state = .listening
        }
    }

    nonisolated func onTextFallback(_ text: String, executedTools: [String]) {
        logger.info("Text fallback: \(text), tools: \(executedTools)")
    }

    nonisolated func onError(_ error: Error) {
        Task { @MainActor in
            self.logger.error("Voice error: \(error)")
            self.state = .idle
        }
    }
}
