//
//  SonioxStreamingService.swift
//  VoiceKeyboard
//
//  Created by Peng Chen on 28/3/26.
//
//  Manages a WebSocket connection to the Soniox streaming STT API.
//  Sends PCM audio frames and surfaces partial / final token results.
//
//  Soniox protocol:
//    1. Connect to wss://api.soniox.com/transcribe-websocket
//    2. First message: JSON config (includes api_key, model, options)
//    3. Subsequent messages: binary PCM chunks (16 kHz, Int16, mono)
//    4. Send empty binary frame to signal end-of-audio
//    5. Server replies with JSON token arrays; tokens with is_final=false
//       are interim ("partial"), is_final=true are committed.
//

import Foundation

// MARK: - Delegate

protocol SonioxStreamingDelegate: AnyObject {
    /// Called on Main thread with the accumulated partial (non-final) text so far.
    func sonioxService(_ service: SonioxStreamingService, didUpdatePartial text: String)
    /// Called on Main thread each time a chunk of final text arrives.
    func sonioxService(_ service: SonioxStreamingService, didFinalizePart text: String)
    /// Called when the WebSocket connection is established and config sent.
    func sonioxServiceDidConnect(_ service: SonioxStreamingService)
    /// Called when the connection closes (normally or on error).
    func sonioxServiceDidDisconnect(_ service: SonioxStreamingService)
    /// Called on any error; the service disconnects automatically.
    func sonioxService(_ service: SonioxStreamingService, didFailWithError error: Error)
}

// MARK: - Service

final class SonioxStreamingService: NSObject {

    weak var delegate: SonioxStreamingDelegate?

    private(set) var isConnected = false

    private let apiKey: String
    private let languageHints: [String]

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?

    // Buffer of final text received since last flush
    private var pendingFinalText = ""

    init(apiKey: String, languageHints: [String] = ["en", "zh"]) {
        self.apiKey = apiKey
        self.languageHints = languageHints
        super.init()
    }

    // MARK: - Lifecycle

    func connect() {
        guard !isConnected else { return }

        let config = URLSessionConfiguration.default
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: .main)

        guard let url = URL(string: "wss://api.soniox.com/transcribe-websocket") else { return }
        webSocketTask = urlSession?.webSocketTask(with: url)
        webSocketTask?.resume()

        sendConfig()
        receiveLoop()
    }

    func disconnect() {
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        tearDown()
    }

    // MARK: - Audio

    /// Send a chunk of raw PCM audio data.
    func sendAudio(_ data: Data) {
        guard isConnected, !data.isEmpty else { return }
        webSocketTask?.send(.data(data)) { [weak self] error in
            if let error { self?.handleError(error) }
        }
    }

    /// Signal end of audio stream so Soniox flushes remaining tokens.
    func finishAudio() {
        guard isConnected else { return }
        webSocketTask?.send(.data(Data())) { [weak self] error in
            if let error { self?.handleError(error) }
        }
    }

    // MARK: - Private helpers

    private func sendConfig() {
        let config: [String: Any] = [
            "api_key": apiKey,
            "model": "soniox_multilingual",
            "language_hints": languageHints,
            "include_nonfinal": true,
            "enable_endpoint_detection": true
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: config),
              let jsonString = String(data: data, encoding: .utf8)
        else { return }

        webSocketTask?.send(.string(jsonString)) { [weak self] error in
            guard let self else { return }
            if let error {
                self.handleError(error)
            } else {
                self.isConnected = true
                self.delegate?.sonioxServiceDidConnect(self)
            }
        }
    }

    private func receiveLoop() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                self.handle(message: message)
                self.receiveLoop()
            case .failure(let error):
                self.handleError(error)
            }
        }
    }

    private func handle(message: URLSessionWebSocketTask.Message) {
        guard case .string(let jsonString) = message,
              let data = jsonString.data(using: .utf8),
              let response = try? JSONDecoder().decode(SonioxResponse.self, from: data)
        else { return }

        let finalTokens   = response.tokens.filter { $0.is_final }
        let partialTokens = response.tokens.filter { !$0.is_final }

        if !finalTokens.isEmpty {
            let finalChunk = finalTokens.map(\.text).joined()
            pendingFinalText += finalChunk
            delegate?.sonioxService(self, didFinalizePart: finalChunk)
        }

        if !partialTokens.isEmpty {
            let partialChunk = partialTokens.map(\.text).joined()
            delegate?.sonioxService(self, didUpdatePartial: partialChunk)
        }
    }

    private func handleError(_ error: Error) {
        delegate?.sonioxService(self, didFailWithError: error)
        tearDown()
        delegate?.sonioxServiceDidDisconnect(self)
    }

    private func tearDown() {
        isConnected = false
        webSocketTask = nil
        urlSession = nil
        pendingFinalText = ""
    }
}

// MARK: - URLSessionWebSocketDelegate

extension SonioxStreamingService: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
                    reason: Data?) {
        tearDown()
        delegate?.sonioxServiceDidDisconnect(self)
    }
}

// MARK: - Response Models

private struct SonioxResponse: Decodable {
    let tokens: [SonioxToken]
}

private struct SonioxToken: Decodable {
    let text: String
    let start_ms: Int
    let end_ms: Int
    let is_final: Bool
}
