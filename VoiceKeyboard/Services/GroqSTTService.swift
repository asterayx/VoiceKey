//
//  GroqSTTService.swift
//  VoiceKeyboard
//
//  REST-based STT provider using Groq's Whisper API.
//  Buffers PCM audio, converts to WAV on finishAudio(), and POSTs
//  to the transcriptions endpoint.
//
//  Endpoint: https://api.groq.com/openai/v1/audio/transcriptions
//

import Foundation

final class GroqSTTService: StreamingSTTProvider {

    weak var delegate: STTProviderDelegate?
    private(set) var isConnected = false

    private let apiKey: String
    private let language: String
    private let prompt: String
    private let model: String

    private var audioChunks: [Data] = []
    private var totalBytes: Int = 0

    private static let endpoint = "https://api.groq.com/openai/v1/audio/transcriptions"

    init(apiKey: String, language: String, prompt: String = "", model: String = "whisper-large-v3") {
        self.apiKey = apiKey
        self.language = language
        self.prompt = prompt
        self.model = model
    }

    // MARK: - StreamingSTTProvider

    func connect() {
        audioChunks = []
        totalBytes = 0
        isConnected = true
        delegate?.sttProviderDidConnect(self)
    }

    func disconnect() {
        audioChunks = []
        totalBytes = 0
        isConnected = false
        delegate?.sttProviderDidDisconnect(self)
    }

    func sendAudio(_ data: Data) {
        guard isConnected, !data.isEmpty else { return }
        // Enforce max buffer size
        guard totalBytes + data.count <= AudioBufferWriter.maxBufferSize else { return }
        audioChunks.append(data)
        totalBytes += data.count
    }

    func finishAudio() {
        guard isConnected else { return }

        let pcmData = audioChunks.reduce(Data()) { $0 + $1 }
        audioChunks = []
        totalBytes = 0

        guard !pcmData.isEmpty else {
            isConnected = false
            delegate?.sttProviderDidDisconnect(self)
            return
        }

        let wavData = AudioBufferWriter.pcmToWAV(pcmData)
        uploadAudio(wavData)
    }

    // MARK: - HTTP upload

    private func uploadAudio(_ wavData: Data) {
        guard let url = URL(string: Self.endpoint) else { return }

        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        var body = Data()
        // file field
        body.appendMultipart(boundary: boundary, name: "file", filename: "audio.wav",
                             contentType: "audio/wav", data: wavData)
        // model field
        body.appendMultipart(boundary: boundary, name: "model", value: model)
        // language field
        if !language.isEmpty {
            body.appendMultipart(boundary: boundary, name: "language", value: language)
        }
        // prompt field (for recognition hints)
        if !prompt.isEmpty {
            body.appendMultipart(boundary: boundary, name: "prompt", value: prompt)
        }
        // response_format
        body.appendMultipart(boundary: boundary, name: "response_format", value: "json")
        // close boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.handleResponse(data: data, response: response, error: error)
            }
        }.resume()
    }

    private func handleResponse(data: Data?, response: URLResponse?, error: Error?) {
        defer {
            isConnected = false
            delegate?.sttProviderDidDisconnect(self)
        }

        if let error {
            delegate?.sttProvider(self, didFailWithError: error)
            return
        }

        guard let data else {
            delegate?.sttProvider(self, didFailWithError: STTError.emptyResponse)
            return
        }

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? ""
            delegate?.sttProvider(self, didFailWithError: STTError.httpError(httpResponse.statusCode, body))
            return
        }

        // Parse {"text": "..."}
        do {
            let result = try JSONDecoder().decode(WhisperResponse.self, from: data)
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                delegate?.sttProvider(self, didFinalizePart: text)
            }
        } catch {
            delegate?.sttProvider(self, didFailWithError: error)
        }
    }
}

// MARK: - Shared types

struct WhisperResponse: Decodable {
    let text: String
}

enum STTError: LocalizedError {
    case emptyResponse
    case httpError(Int, String)

    var errorDescription: String? {
        switch self {
        case .emptyResponse:
            return "ASR 服务返回空响应"
        case .httpError(let code, let body):
            return "ASR 请求失败 (HTTP \(code)): \(body.prefix(200))"
        }
    }
}

// MARK: - Multipart helpers

private extension Data {
    mutating func appendMultipart(boundary: String, name: String, filename: String,
                                  contentType: String, data: Data) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        append("Content-Type: \(contentType)\r\n\r\n".data(using: .utf8)!)
        append(data)
        append("\r\n".data(using: .utf8)!)
    }

    mutating func appendMultipart(boundary: String, name: String, value: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append("\(value)\r\n".data(using: .utf8)!)
    }
}
