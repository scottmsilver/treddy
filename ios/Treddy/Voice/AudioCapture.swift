import AVFoundation
import AudioToolbox
import os

/// Captures PCM16 mono audio from the microphone at 16kHz using a raw
/// `kAudioUnitSubType_VoiceProcessingIO` AudioUnit for hardware echo cancellation.
///
/// The AudioUnit handles mic input only (bus 1 enabled, bus 0 disabled).
/// AEC still works because VoiceProcessingIO sees all audio played through
/// the hardware by the AVAudioEngine that AudioPlayer attaches to.
///
/// A shared AVAudioEngine is created (but not used for mic capture) so that
/// AudioPlayer can attach its player node for playback.
final class AudioCapture: @unchecked Sendable {
    static let sampleRate: Double = 16000
    private static let silenceRmsThreshold: Float = 800

    private static let logger = Logger(subsystem: "com.treddy", category: "AudioCapture")

    /// The shared engine -- AudioPlayer attaches its node here for playback.
    private(set) var engine: AVAudioEngine?

    private var audioUnit: AudioUnit?
    /// Retained reference passed to the render callback. Released in tearDown().
    private var retainedSelf: Unmanaged<AudioCapture>?
    private var isRecording = false

    var onAudioChunk: ((String) -> Void)?
    /// RMS of the most recent audio chunk (PCM16 scale, 0-32767).
    private(set) var lastChunkRms: Float = 0
    private(set) var silenceStartMs: Int64 = 0
    private(set) var lastSpeechMs: Int64 = 0
    private var wasSpeaking = false
    private var silentChunks = 0

    // -- Resampling state (persisted across callbacks) --
    private var converter: AVAudioConverter?
    private var nativeSampleRate: Double = 0
    private var nativeFormat: AVAudioFormat?
    private var targetFormat: AVAudioFormat?

    // -- Pre-allocated buffers for the render callback --
    // These are set up in start() at the actual native rate.
    private var renderBufferList: UnsafeMutableAudioBufferListPointer?
    private var renderBufferData: UnsafeMutablePointer<Int16>?
    private var renderBufferFrameCount: UInt32 = 0

    private var processBufferCount = 0

    // -- Processing queue for resampling off the audio thread --
    private let processingQueue = DispatchQueue(label: "com.treddy.audio.processing", qos: .userInteractive)

    // MARK: - Public Interface

    /// Pre-create the AVAudioEngine (for player) and the AudioUnit (for mic).
    /// Init order: engine first (prevents quiet playback volume on iOS), then AudioUnit.
    func warmUp() {
        guard audioUnit == nil else { return }

        // 1. Create AVAudioEngine for playback (AudioPlayer attaches here)
        let eng = AVAudioEngine()
        engine = eng

        // 2. Create the VoiceProcessingIO AudioUnit for mic capture
        var desc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_VoiceProcessingIO,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )

        guard let component = AudioComponentFindNext(nil, &desc) else {
            Self.logger.error("Failed to find VoiceProcessingIO component")
            return
        }

        var unit: AudioUnit?
        let createStatus = AudioComponentInstanceNew(component, &unit)
        guard createStatus == noErr, let unit = unit else {
            Self.logger.error("Failed to create AudioUnit: \(createStatus)")
            return
        }

        // Enable input on bus 1
        var enableInput: UInt32 = 1
        var status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Input,
            1,  // bus 1 = mic input
            &enableInput,
            UInt32(MemoryLayout<UInt32>.size)
        )
        guard status == noErr else {
            Self.logger.error("Failed to enable input on bus 1: \(status)")
            AudioComponentInstanceDispose(unit)
            return
        }

        // Disable output on bus 0 (we don't play through this AudioUnit)
        var disableOutput: UInt32 = 0
        status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Output,
            0,  // bus 0 = speaker output
            &disableOutput,
            UInt32(MemoryLayout<UInt32>.size)
        )
        guard status == noErr else {
            Self.logger.error("Failed to disable output on bus 0: \(status)")
            AudioComponentInstanceDispose(unit)
            return
        }

        audioUnit = unit

        // Configure audio session + full AudioUnit setup now (so start() is instant)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)

            nativeSampleRate = session.sampleRate
            if nativeSampleRate == 0 { nativeSampleRate = 48000 }

            // Set stream format on output scope of bus 1
            var streamFormat = AudioStreamBasicDescription(
                mSampleRate: nativeSampleRate,
                mFormatID: kAudioFormatLinearPCM,
                mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
                mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2,
                mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0
            )
            var status = AudioUnitSetProperty(
                unit, kAudioUnitProperty_StreamFormat,
                kAudioUnitScope_Output, 1,
                &streamFormat, UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            )
            guard status == noErr else {
                Self.logger.error("Failed to set stream format: \(status)")
                AudioComponentInstanceDispose(unit); audioUnit = nil; return
            }

            // Resampler
            nativeFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: nativeSampleRate, channels: 1, interleaved: true)
            targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: Self.sampleRate, channels: 1, interleaved: true)
            if let nf = nativeFormat, let tf = targetFormat {
                converter = AVAudioConverter(from: nf, to: tf)
            }

            // Pre-allocate render buffer
            allocateRenderBuffer(frameCount: UInt32(nativeSampleRate * 0.2))

            // Input callback — use passRetained so the AudioUnit keeps us alive
            retainedSelf = Unmanaged.passRetained(self)
            var callbackStruct = AURenderCallbackStruct(
                inputProc: Self.renderCallback,
                inputProcRefCon: retainedSelf!.toOpaque()
            )
            status = AudioUnitSetProperty(
                unit, kAudioOutputUnitProperty_SetInputCallback,
                kAudioUnitScope_Global, 1,
                &callbackStruct, UInt32(MemoryLayout<AURenderCallbackStruct>.size)
            )
            guard status == noErr else {
                Self.logger.error("Failed to set input callback: \(status)")
                retainedSelf?.release(); retainedSelf = nil
                AudioComponentInstanceDispose(unit); audioUnit = nil; return
            }

            // Initialize (but don't start yet — start() does that)
            status = AudioUnitInitialize(unit)
            guard status == noErr else {
                Self.logger.error("AudioUnitInitialize failed: \(status)")
                retainedSelf?.release(); retainedSelf = nil
                AudioComponentInstanceDispose(unit); audioUnit = nil; return
            }

        } catch {
            Self.logger.error("Audio session setup failed: \(error.localizedDescription)")
            retainedSelf?.release(); retainedSelf = nil
            AudioComponentInstanceDispose(unit); audioUnit = nil
        }

        Self.logger.info("warmUp done: AudioUnit initialized at \(self.nativeSampleRate)Hz, engine ready")
    }

    /// Start capturing audio. Returns false if not warmed up or mic unavailable.
    /// Near-instant — all heavy setup was done in warmUp().
    func start() -> Bool {
        guard let unit = audioUnit, !isRecording else { return false }

        let status = AudioOutputUnitStart(unit)
        guard status == noErr else {
            Self.logger.error("AudioOutputUnitStart failed: \(status)")
            return false
        }

        // Start AVAudioEngine for playback
        do { try engine?.start() } catch {
            Self.logger.error("Engine start failed: \(error)")
        }

        isRecording = true
        silentChunks = 0
        wasSpeaking = false
        processBufferCount = 0
        return true
    }

    /// Stop capturing.
    func stop() {
        guard isRecording else { return }
        if let unit = audioUnit {
            AudioOutputUnitStop(unit)
        }
        engine?.stop()
        isRecording = false
    }

    /// Release all resources.
    func tearDown() {
        stop()
        if let unit = audioUnit {
            AudioUnitUninitialize(unit)
            AudioComponentInstanceDispose(unit)
            audioUnit = nil
        }
        retainedSelf?.release()
        retainedSelf = nil
        engine = nil
        converter = nil
        nativeFormat = nil
        targetFormat = nil
        deallocateRenderBuffer()
    }

    // MARK: - Render Buffer Management

    private func allocateRenderBuffer(frameCount: UInt32) {
        deallocateRenderBuffer()
        renderBufferFrameCount = frameCount
        let byteCount = Int(frameCount) * MemoryLayout<Int16>.size
        renderBufferData = UnsafeMutablePointer<Int16>.allocate(capacity: Int(frameCount))
        renderBufferData?.initialize(repeating: 0, count: Int(frameCount))

        // Build an AudioBufferList with one buffer pointing to our pre-allocated memory
        let ablMemory = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        ablMemory.initialize(to: AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(
                mNumberChannels: 1,
                mDataByteSize: UInt32(byteCount),
                mData: UnsafeMutableRawPointer(renderBufferData)
            )
        ))
        renderBufferList = UnsafeMutableAudioBufferListPointer(ablMemory)
    }

    private func deallocateRenderBuffer() {
        if let data = renderBufferData {
            data.deallocate()
            renderBufferData = nil
        }
        if let abl = renderBufferList {
            abl.unsafeMutablePointer.deallocate()
            renderBufferList = nil
        }
        renderBufferFrameCount = 0
    }

    // MARK: - Render Callback (C function, real-time audio thread)

    /// Called by the AudioUnit on the real-time audio thread.
    /// No allocations, no locks, no ObjC messaging.
    private static let renderCallback: AURenderCallback = {
        (inRefCon, ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, ioData) -> OSStatus in

        let capture = Unmanaged<AudioCapture>.fromOpaque(inRefCon).takeUnretainedValue()

        guard let abl = capture.renderBufferList, inNumberFrames <= capture.renderBufferFrameCount else {
            return kAudioUnitErr_TooManyFramesToProcess
        }

        // Reset the buffer size for this callback
        let byteCount = Int(inNumberFrames) * MemoryLayout<Int16>.size
        abl[0].mDataByteSize = UInt32(byteCount)

        // Pull audio data from the AudioUnit
        guard let unit = capture.audioUnit else { return noErr }
        let status = AudioUnitRender(
            unit,
            ioActionFlags,
            inTimeStamp,
            inBusNumber,
            inNumberFrames,
            abl.unsafeMutablePointer
        )
        guard status == noErr else { return status }

        // Copy the rendered data and dispatch for processing off the audio thread.
        // The copy is a fast memcpy of the PCM16 bytes -- no heap allocation patterns
        // that would trigger the real-time thread checker.
        guard let srcData = capture.renderBufferData else { return noErr }
        let dataCopy = Data(bytes: srcData, count: byteCount)
        let frameCount = inNumberFrames
        let sampleRate = capture.nativeSampleRate

        capture.processingQueue.async {
            capture.processRawBuffer(dataCopy, frameCount: frameCount, sampleRate: sampleRate)
        }

        return noErr
    }

    // MARK: - Audio Processing (off real-time thread)

    private func processRawBuffer(_ data: Data, frameCount: UInt32, sampleRate: Double) {
        processBufferCount += 1
        guard frameCount > 0 else { return }

        let resampled: Data

        if let converter = converter,
           let nativeFormat = nativeFormat,
           let targetFormat = targetFormat,
           abs(sampleRate - Self.sampleRate) > 1.0 {

            // Create an AVAudioPCMBuffer from the raw data for the converter input
            let outputFrameCount = AVAudioFrameCount(Double(frameCount) * Self.sampleRate / sampleRate)
            guard outputFrameCount > 0 else { return }

            guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: nativeFormat, frameCapacity: frameCount) else { return }
            inputBuffer.frameLength = frameCount
            data.withUnsafeBytes { raw in
                if let baseAddress = raw.baseAddress {
                    memcpy(inputBuffer.int16ChannelData![0], baseAddress, Int(frameCount) * 2)
                }
            }

            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCount) else { return }

            var inputConsumed = false
            var error: NSError?
            let convertStatus = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
                if inputConsumed {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                inputConsumed = true
                outStatus.pointee = .haveData
                return inputBuffer
            }

            guard convertStatus != .error, error == nil, outputBuffer.frameLength > 0 else {
                if let error = error {
                    Self.logger.error("Resample error: \(error.localizedDescription)")
                }
                return
            }

            let outByteCount = Int(outputBuffer.frameLength) * 2
            resampled = Data(bytes: outputBuffer.int16ChannelData![0], count: outByteCount)
        } else {
            // No resampling needed -- native rate is already 16kHz
            resampled = data
        }

        // RMS + speech detection
        let sampleCount = resampled.count / 2
        guard sampleCount > 0 else { return }

        var sumSquares: Float = 0
        resampled.withUnsafeBytes { raw in
            let samples = raw.bindMemory(to: Int16.self)
            for i in 0..<sampleCount {
                let f = Float(samples[i])
                sumSquares += f * f
            }
        }
        let rms = sqrtf(sumSquares / Float(sampleCount))
        lastChunkRms = rms
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

        // Emit base64 PCM16 at 16kHz
        let base64 = resampled.base64EncodedString()
        onAudioChunk?(base64)
    }
}
