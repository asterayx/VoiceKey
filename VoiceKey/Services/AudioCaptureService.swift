//
//  AudioCaptureService.swift
//  VoiceKey
//
//  Created by Peng Chen on 28/3/26.
//
//  Captures microphone audio via AVAudioEngine and converts it to
//  16 kHz / 16-bit mono PCM suitable for streaming STT services.
//  Integrates SilenceDetector for automatic silence timeout.
//

import AVFoundation

protocol AudioCaptureDelegate: AnyObject {
    func audioCaptureService(_ service: AudioCaptureService, didCapture pcmData: Data)
    func audioCaptureService(_ service: AudioCaptureService, didFailWithError error: Error)
    func audioCaptureServiceDidStop(_ service: AudioCaptureService)
    /// Called when silence exceeds the configured timeout.
    func audioCaptureServiceDidDetectSilenceTimeout(_ service: AudioCaptureService)
}

// Default implementation so existing conformers don't break
extension AudioCaptureDelegate {
    func audioCaptureServiceDidDetectSilenceTimeout(_ service: AudioCaptureService) {}
}

final class AudioCaptureService {

    weak var delegate: AudioCaptureDelegate?

    /// Silence detector — configure threshold and timeout before starting.
    let silenceDetector = SilenceDetector()

    private let audioEngine = AVAudioEngine()
    private var audioConverter: AVAudioConverter?
    private(set) var isRunning = false

    // Soniox / Deepgram / Groq / Cerebras expect: 16 kHz, Int16, mono
    static let targetSampleRate: Double = 16_000
    private let tapBufferSize: AVAudioFrameCount = 4096

    // MARK: - Public API

    func startCapture() throws {
        guard !isRunning else { return }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
        try session.setActive(true)

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Self.targetSampleRate,
            channels: 1,
            interleaved: true
        ) else { throw CaptureError.formatUnsupported }

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw CaptureError.converterFailed
        }
        audioConverter = converter

        // Reset silence detector
        silenceDetector.reset()
        silenceDetector.onSilenceTimeout = { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async {
                self.delegate?.audioCaptureServiceDidDetectSilenceTimeout(self)
            }
        }

        inputNode.installTap(onBus: 0, bufferSize: tapBufferSize, format: inputFormat) { [weak self] buffer, _ in
            self?.process(buffer: buffer, converter: converter, targetFormat: targetFormat)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRunning = true
    }

    func stopCapture() {
        guard isRunning else { return }
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        audioConverter = nil
        isRunning = false
        silenceDetector.reset()
        // Do NOT deactivate audio session — background audio residency
        // requires the session to stay active for the main app to remain alive.
        delegate?.audioCaptureServiceDidStop(self)
    }

    // MARK: - Private

    private func process(buffer: AVAudioPCMBuffer,
                         converter: AVAudioConverter,
                         targetFormat: AVAudioFormat) {
        let ratio = Self.targetSampleRate / buffer.format.sampleRate
        let outputFrames = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        guard outputFrames > 0,
              let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat,
                                                  frameCapacity: outputFrames)
        else { return }

        var consumedInput = false
        var conversionError: NSError?

        converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            if consumedInput {
                outStatus.pointee = .noDataNow
                return nil
            }
            outStatus.pointee = .haveData
            consumedInput = true
            return buffer
        }

        if let error = conversionError {
            delegate?.audioCaptureService(self, didFailWithError: error)
            return
        }

        guard let channelData = outputBuffer.int16ChannelData else { return }
        let byteCount = Int(outputBuffer.frameLength) * MemoryLayout<Int16>.size
        let data = Data(bytes: channelData[0], count: byteCount)

        // Feed silence detector
        silenceDetector.process(data)

        delegate?.audioCaptureService(self, didCapture: data)
    }

    // MARK: - Errors

    enum CaptureError: LocalizedError {
        case formatUnsupported
        case converterFailed

        var errorDescription: String? {
            switch self {
            case .formatUnsupported: return "Audio format not supported on this device."
            case .converterFailed:   return "Could not create audio sample rate converter."
            }
        }
    }
}
