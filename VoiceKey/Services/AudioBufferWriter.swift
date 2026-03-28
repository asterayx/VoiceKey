//
//  AudioBufferWriter.swift
//  VoiceKey
//
//  Converts accumulated PCM Int16 mono chunks into a WAV-format Data blob.
//  Used by REST-based ASR providers (Groq, Cerebras) that require file upload.
//

import Foundation

enum AudioBufferWriter {

    /// Maximum recording duration in seconds for REST providers.
    static let maxRecordingSeconds: Double = 120

    /// Maximum buffer size in bytes (120s × 16kHz × 2 bytes = ~3.84 MB).
    static let maxBufferSize: Int = Int(maxRecordingSeconds * 16_000) * 2

    /// Wrap raw PCM Int16 mono 16kHz data in a WAV container.
    /// - Parameter pcmData: Raw PCM samples (16-bit, mono, 16 kHz).
    /// - Returns: Complete WAV file data with 44-byte header.
    static func pcmToWAV(_ pcmData: Data) -> Data {
        let sampleRate: UInt32 = 16_000
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample) / 8
        let blockAlign = channels * bitsPerSample / 8
        let dataSize = UInt32(pcmData.count)
        let fileSize = 36 + dataSize

        var header = Data(capacity: 44)

        // RIFF header
        header.append(contentsOf: "RIFF".utf8)
        header.append(littleEndian: fileSize)
        header.append(contentsOf: "WAVE".utf8)

        // fmt chunk
        header.append(contentsOf: "fmt ".utf8)
        header.append(littleEndian: UInt32(16))       // chunk size
        header.append(littleEndian: UInt16(1))        // PCM format
        header.append(littleEndian: channels)
        header.append(littleEndian: sampleRate)
        header.append(littleEndian: byteRate)
        header.append(littleEndian: blockAlign)
        header.append(littleEndian: bitsPerSample)

        // data chunk
        header.append(contentsOf: "data".utf8)
        header.append(littleEndian: dataSize)

        return header + pcmData
    }
}

// MARK: - Data extension for little-endian writes

private extension Data {
    mutating func append(littleEndian value: UInt16) {
        var v = value.littleEndian
        append(Data(bytes: &v, count: 2))
    }

    mutating func append(littleEndian value: UInt32) {
        var v = value.littleEndian
        append(Data(bytes: &v, count: 4))
    }
}
