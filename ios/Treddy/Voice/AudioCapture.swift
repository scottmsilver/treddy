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
        // Use nil format to get the node's native format. Requesting a specific
        // format (like 16kHz PCM16) crashes on simulators and some devices where
        // the hardware doesn't support that format natively. We convert in processBuffer.
        inputNode.installTap(onBus: 0, bufferSize: Self.bufferSize, format: nil) { [weak self] buffer, _ in
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
        // Convert native format (typically 48kHz Float32) to 16kHz PCM16 for Gemini
        let nativeSampleRate = buffer.format.sampleRate
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        // Get float samples (works for both Float32 and Int16 native formats)
        var floatSamples: [Float]
        if let floatData = buffer.floatChannelData {
            floatSamples = Array(UnsafeBufferPointer(start: floatData[0], count: frameCount))
        } else if let int16Data = buffer.int16ChannelData {
            floatSamples = (0..<frameCount).map { Float(int16Data[0][$0]) / 32768.0 }
        } else {
            return
        }

        // Downsample to 16kHz if needed
        let ratio = nativeSampleRate / Self.sampleRate
        let outputCount: Int
        let resampled: [Int16]

        if ratio > 1.01 {
            outputCount = Int(Double(frameCount) / ratio)
            resampled = (0..<outputCount).map { i in
                let pos = Double(i) * ratio
                let idx = Int(pos)
                let frac = Float(pos - Double(idx))
                let s: Float
                if idx + 1 < frameCount {
                    s = floatSamples[idx] * (1 - frac) + floatSamples[idx + 1] * frac
                } else {
                    s = floatSamples[idx]
                }
                return Int16(clamping: Int(s * 32767))
            }
        } else {
            outputCount = frameCount
            resampled = floatSamples.map { Int16(clamping: Int($0 * 32767)) }
        }

        // RMS for speech detection (on resampled PCM16)
        var sumSquares: Float = 0
        for s in resampled {
            let f = Float(s)
            sumSquares += f * f
        }
        let rms = sqrtf(sumSquares / Float(outputCount))
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
        let data = resampled.withUnsafeBytes { Data($0) }
        let base64 = data.base64EncodedString()
        onAudioChunk?(base64)
    }
}
