//
//  StreamingSTTProvider.swift
//  VoiceKeyboard
//
//  Provider-agnostic protocol for streaming speech-to-text services.
//  Supports both WebSocket-streaming (Soniox) and REST-based (Groq, Cerebras)
//  providers behind the same interface.
//

import Foundation

// MARK: - Delegate

protocol STTProviderDelegate: AnyObject {
    /// Partial (non-final) text update — streaming providers only.
    func sttProvider(_ provider: any StreamingSTTProvider, didUpdatePartial text: String)
    /// Finalized text chunk.
    func sttProvider(_ provider: any StreamingSTTProvider, didFinalizePart text: String)
    /// Connection/session established.
    func sttProviderDidConnect(_ provider: any StreamingSTTProvider)
    /// Connection/session ended.
    func sttProviderDidDisconnect(_ provider: any StreamingSTTProvider)
    /// Error occurred; provider disconnects automatically.
    func sttProvider(_ provider: any StreamingSTTProvider, didFailWithError error: Error)
}

// MARK: - Provider Protocol

protocol StreamingSTTProvider: AnyObject {
    var delegate: STTProviderDelegate? { get set }
    var isConnected: Bool { get }

    /// Establish connection / prepare session.
    func connect()
    /// Tear down connection.
    func disconnect()
    /// Send a chunk of raw PCM audio (16 kHz, Int16, mono).
    func sendAudio(_ data: Data)
    /// Signal end of audio so the provider flushes remaining results.
    func finishAudio()
}
