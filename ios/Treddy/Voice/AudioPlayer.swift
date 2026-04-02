import AVFoundation
import os

/// Plays streamed 24kHz PCM16 mono audio from Gemini responses.
/// Prebuffers 150ms before starting playback.
final class AudioPlayer: @unchecked Sendable {
    private let logger = Logger(subsystem: "com.treddy", category: "AudioPlayer")

    static let sampleRate: Double = 24000
    private static let prebufferMs: Int = 150
    private static let prebufferBytes: Int = Int(24000 * 2 * 150 / 1000) // 7200 bytes

    private var engine: AVAudioEngine?
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
            logger.info("AudioPlayer ready at \(Self.sampleRate)Hz")
        } catch {
            logger.error("AudioPlayer setup failed: \(error)")
        }
    }

    /// Enqueue a base64-encoded PCM16 chunk (24kHz).
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

        // Write immediately if prebuffer already done
        flushPending()
    }

    /// Flush and stop all pending playback (barge-in).
    func flush() {
        playerNode?.stop()
        pendingData.removeAll()
        prebufferDone = false
        isPlaying = false
        playerNode?.play() // restart for next turn
    }

    /// Signal that no more audio is coming for this turn.
    func drain() {
        if !pendingData.isEmpty {
            prebufferDone = true
            flushPending()
        }
        // Schedule completion callback
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.onPlaybackFinished?()
        }
    }

    func tearDown() {
        playerNode?.stop()
        engine?.stop()
        engine = nil
        playerNode = nil
    }

    private func flushPending() {
        guard let playerNode = playerNode, !pendingData.isEmpty else { return }

        let frameCount = AVAudioFrameCount(pendingData.count / 2) // 2 bytes per sample
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
