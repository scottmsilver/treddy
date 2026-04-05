import AVFoundation
import os

/// Plays streamed 24kHz PCM16 mono audio from Gemini responses.
/// Attaches to an external AVAudioEngine (shared with AudioCapture)
/// so that iOS echo cancellation works across mic + speaker.
final class AudioPlayer: @unchecked Sendable {
    private let logger = Logger(subsystem: "com.treddy", category: "AudioPlayer")

    static let sampleRate: Double = 24000
    private static let prebufferMs: Int = 150
    private static let prebufferBytes: Int = Int(24000 * 2 * 150 / 1000) // 7200 bytes

    private weak var engine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private let format: AVAudioFormat
    private var pendingData = Data()
    private var isPlaying = false
    private var prebufferDone = false

    var onPlaybackStarted: (() -> Void)?
    var onPlaybackFinished: (() -> Void)?

    init() {
        format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Self.sampleRate,
            channels: 1,
            interleaved: true
        )!
    }

    /// Attach player node to a shared engine (preferred — enables AEC).
    func setup(sharedEngine: AVAudioEngine) {
        let player = AVAudioPlayerNode()
        sharedEngine.attach(player)
        sharedEngine.connect(player, to: sharedEngine.mainMixerNode, format: format)

        engine = sharedEngine
        playerNode = player
        logger.info("Attached to shared engine at \(Self.sampleRate)Hz")
    }

    /// Fallback: create own engine (no AEC with capture).
    func setup() {
        let eng = AVAudioEngine()
        let player = AVAudioPlayerNode()
        eng.attach(player)
        eng.connect(player, to: eng.mainMixerNode, format: format)

        do {
            try eng.start()
            engine = eng
            playerNode = player
            player.play()
            logger.info("Own engine at \(Self.sampleRate)Hz (no AEC)")
        } catch {
            logger.error("Setup failed: \(error)")
        }
    }

    func enqueue(_ base64: String) {
        guard let data = Data(base64Encoded: base64) else { return }
        pendingData.append(data)

        if !prebufferDone {
            if pendingData.count >= Self.prebufferBytes {
                prebufferDone = true
                flushPending()
                onPlaybackStarted?()
            }
            return
        }

        flushPending()
    }

    func flush() {
        playerNode?.stop()
        pendingData.removeAll()
        prebufferDone = false
        isPlaying = false
        playerNode?.play()
    }

    func drain() {
        if !pendingData.isEmpty {
            prebufferDone = true
            flushPending()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.onPlaybackFinished?()
        }
    }

    func tearDown() {
        playerNode?.stop()
        if let node = playerNode, let eng = engine {
            eng.detach(node)
        }
        playerNode = nil
        engine = nil
    }

    private func flushPending() {
        guard let playerNode = playerNode, !pendingData.isEmpty else { return }

        // Ensure player node is playing (needed for shared engine — engine starts after setup)
        if !playerNode.isPlaying {
            playerNode.play()
        }

        let frameCount = AVAudioFrameCount(pendingData.count / 2)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount

        pendingData.withUnsafeBytes { raw in
            if let baseAddress = raw.baseAddress {
                memcpy(buffer.int16ChannelData![0], baseAddress, pendingData.count)
            }
        }

        playerNode.scheduleBuffer(buffer)
        pendingData.removeAll()
        isPlaying = true
    }
}
