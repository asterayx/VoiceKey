//
//  SilenceDetector.swift
//  VoiceKeyboard
//
//  Monitors PCM audio energy (RMS) and detects silence.
//  Fires a callback after a configurable duration of continuous silence.
//

import Foundation

final class SilenceDetector {

    /// Called on the caller's thread when silence exceeds the timeout.
    var onSilenceTimeout: (() -> Void)?

    /// RMS threshold below which audio is considered silence (0–32767 range for Int16).
    /// Default ~150 is conservative — picks up most speech but ignores ambient noise.
    var threshold: Int16 = 150

    /// Seconds of continuous silence before firing timeout.
    var timeoutSeconds: Double = 3.0

    private var silenceStartDate: Date?
    private var hasFired = false

    // MARK: - Public API

    /// Feed a chunk of PCM Int16 mono audio data.
    /// Call this from the audio tap callback.
    func process(_ pcmData: Data) {
        let rms = Self.calculateRMS(pcmData)

        if rms < threshold {
            // Silent frame
            if silenceStartDate == nil {
                silenceStartDate = Date()
            }
            if !hasFired, let start = silenceStartDate,
               Date().timeIntervalSince(start) >= timeoutSeconds {
                hasFired = true
                onSilenceTimeout?()
            }
        } else {
            // Speech detected — reset
            silenceStartDate = nil
            hasFired = false
        }
    }

    /// Reset detector state (call when starting a new recording session).
    func reset() {
        silenceStartDate = nil
        hasFired = false
    }

    // MARK: - RMS calculation

    /// Calculate root-mean-square of Int16 PCM samples.
    static func calculateRMS(_ data: Data) -> Int16 {
        let sampleCount = data.count / MemoryLayout<Int16>.size
        guard sampleCount > 0 else { return 0 }

        var sumOfSquares: Int64 = 0
        data.withUnsafeBytes { rawBuffer in
            let samples = rawBuffer.bindMemory(to: Int16.self)
            for i in 0..<sampleCount {
                let s = Int64(samples[i])
                sumOfSquares += s * s
            }
        }
        let meanSquare = sumOfSquares / Int64(sampleCount)
        return Int16(clamping: Int64(sqrt(Double(meanSquare))))
    }
}
