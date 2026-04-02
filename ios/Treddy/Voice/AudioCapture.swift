import AVFoundation
import os

/// Captures PCM16 mono audio from the microphone at 16kHz.
/// Pre-warms the AudioEngine so start() is near-instant.
final class AudioCapture: @unchecked Sendable {
    private let logger = Logger(subsystem: "com.treddy", category: "AudioCapture")

    static let sampleRate: Double = 16000
    static let bufferSize: AVAudioFrameCount = 2048 // 128ms @ 16kHz
    private static let silenceRmsThreshold: Float = 800

    private var engine: AVAudioEngine?
    private var isRecording = false

    var onAudioChunk: ((String) -> Void)? // base64 PCM16 chunk
    private(set) var silenceStartMs: Int64 = 0
    private(set) var lastSpeechMs: Int64 = 0
    private var wasSpeaking = false
    private var silentChunks = 0

    /// Pre-create the audio engine without starting capture.
    func warmUp() {
        guard engine == nil else { return }
        let eng = AVAudioEngine()
        engine = eng

        let inputNode = eng.inputNode
        let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Self.sampleRate,
            channels: 1,
            interleaved: true
        )!

        inputNode.installTap(onBus: 0, bufferSize: Self.bufferSize, format: format) { [weak self] buffer, _ in
            self?.processBuffer(buffer)
        }

        logger.info("AudioEngine warmed up at \(Self.sampleRate)Hz")
    }

    /// Start capturing audio. Returns false if not warmed up or mic unavailable.
    func start() -> Bool {
        guard let engine = engine, !isRecording else { return false }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
            try engine.start()
            isRecording = true
            silentChunks = 0
            wasSpeaking = false
            logger.info("Recording started")
            return true
        } catch {
            logger.error("Failed to start: \(error)")
            return false
        }
    }

    /// Stop capturing.
    func stop() {
        guard isRecording else { return }
        engine?.stop()
        isRecording = false
        logger.info("Recording stopped")
    }

    /// Release all resources.
    func tearDown() {
        stop()
        engine?.inputNode.removeTap(onBus: 0)
        engine = nil
    }

    private func processBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let int16Data = buffer.int16ChannelData else { return }
        let count = Int(buffer.frameLength)
        let samples = int16Data[0]

        // RMS for speech detection
        var sumSquares: Float = 0
        for i in 0..<count {
            let s = Float(samples[i])
            sumSquares += s * s
        }
        let rms = sqrtf(sumSquares / Float(count))
        let now = Int64(Date().timeIntervalSince1970 * 1000)

        if rms >= Self.silenceRmsThreshold {
            wasSpeaking = true
            lastSpeechMs = now
            silentChunks = 0
        } else {
            silentChunks += 1
            if silentChunks >= 2 && wasSpeaking {
                wasSpeaking = false
                silenceStartMs = now
            }
        }

        // Base64 encode raw PCM16 bytes
        let byteCount = count * 2
        let data = Data(bytes: samples, count: byteCount)
        let base64 = data.base64EncodedString()
        onAudioChunk?(base64)
    }
}
