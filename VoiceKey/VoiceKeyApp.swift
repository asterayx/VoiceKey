//
//  VoiceKeyApp.swift
//  VoiceKey
//
//  Created by Peng Chen on 28/3/26.
//
//  Main app entry point. Manages background audio session and handles
//  URL Scheme activation from the keyboard extension.
//
//  Background Audio Residency:
//    After first activation, the app maintains AVAudioEngine in background
//    via UIBackgroundModes: audio. The keyboard extension sends commands
//    via Darwin Notification; this app records, runs ASR, and writes
//    results to App Group UserDefaults.
//

import SwiftUI

@main
struct VoiceKeyApp: App {
    @StateObject private var audioManager = BackgroundAudioManager.shared
    @State private var showVoiceInput = false

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ContentView()
                    .navigationDestination(isPresented: $showVoiceInput) {
                        VoiceInputView()
                    }
            }
            .onOpenURL { url in
                handleURL(url)
            }
            .onAppear {
                audioManager.startListeningForCommands()
            }
        }
    }

    private func handleURL(_ url: URL) {
        guard url.scheme == "voicekey" else { return }

        switch url.host {
        case "activate":
            // Keyboard requested activation — start background audio session
            audioManager.activate()
            // Show voice input UI briefly so user sees confirmation
            showVoiceInput = true
        case "record":
            // Legacy / direct recording request
            audioManager.activate()
            showVoiceInput = true
        case "command":
            // M7: voice command editing — placeholder
            audioManager.activate()
            showVoiceInput = true
        default:
            break
        }
    }
}

// MARK: - Background Audio Manager

/// Manages the background audio session lifecycle.
/// Keeps AVAudioEngine alive in background via UIBackgroundModes: audio.
/// Listens for Darwin Notification commands from keyboard extension.
final class BackgroundAudioManager: ObservableObject {

    static let shared = BackgroundAudioManager()

    @Published var isActivated = false
    @Published var isRecording = false

    private let audioService = AudioCaptureService()
    private var sttProvider: (any StreamingSTTProvider)?
    private var heartbeatTimer: Timer?
    private var lastCommandTimestamp: TimeInterval = 0

    // STT accumulation
    private var committedText = ""
    private var partialText = ""

    private init() {}

    // MARK: - Activation

    /// Activate background audio session. Called from URL Scheme handler.
    func activate() {
        guard !isActivated else { return }
        isActivated = true

        // Start heartbeat so keyboard knows we're alive
        startHeartbeat()

        // Reset session state
        VoiceKeyContract.resetSession()
    }

    // MARK: - Command Listening

    /// Start listening for Darwin Notification commands from keyboard.
    func startListeningForCommands() {
        VoiceKeyContract.observeNotification(VoiceKeyContract.notifyCommand) { [weak self] in
            self?.handleCommand()
        }
    }

    private func handleCommand() {
        guard let command = VoiceKeyContract.currentCommand() else { return }
        let timestamp = VoiceKeyContract.currentCommandTimestamp()

        // Dedup: ignore already-processed commands
        guard timestamp > lastCommandTimestamp else { return }
        lastCommandTimestamp = timestamp

        VoiceKeyContract.clearCommand()

        switch command {
        case .startRecording:
            startRecording()
        case .stopRecording:
            stopRecording()
        case .cancel:
            cancelRecording()
        }
    }

    // MARK: - Recording

    private func startRecording() {
        guard !isRecording else { return }

        let settings = SettingsStore.shared
        let apiKey = settings.activeAPIKey

        guard !apiKey.isEmpty else {
            VoiceKeyContract.setError("API Key 未配置，请打开 VoiceKey App 设置")
            return
        }

        // Ensure audio session is active
        if !isActivated { activate() }

        committedText = ""
        partialText = ""

        // Create STT provider
        let provider = STTProviderFactory.makeProvider(
            engine: settings.sttEngine,
            apiKey: apiKey,
            languages: settings.activeLanguages,
            model: settings.sttModel.isEmpty ? nil : settings.sttModel
        )

        guard let provider else {
            VoiceKeyContract.setError("\(settings.sttEngine.displayName) 初始化失败")
            return
        }

        provider.delegate = self
        sttProvider = provider
        provider.connect()

        audioService.delegate = self
        audioService.silenceDetector.timeoutSeconds = settings.silenceTimeoutSeconds

        do {
            try audioService.startCapture()
        } catch {
            VoiceKeyContract.setError("麦克风启动失败: \(error.localizedDescription)")
            provider.disconnect()
            sttProvider = nil
            return
        }

        isRecording = true
        VoiceKeyContract.setStatus(.recording)

        // Keep screen on while recording in foreground
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = true
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        audioService.stopCapture()
        isRecording = false

        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = false
        }

        if SettingsStore.shared.sttEngine.supportsStreaming {
            sttProvider?.finishAudio()
            VoiceKeyContract.setStatus(.processing)
            // Give streaming provider a moment to flush final tokens
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.finalizeResult()
            }
        } else {
            sttProvider?.finishAudio()
            VoiceKeyContract.setStatus(.processing)
        }
    }

    private func cancelRecording() {
        audioService.stopCapture()
        sttProvider?.disconnect()
        sttProvider = nil
        isRecording = false
        committedText = ""
        partialText = ""
        VoiceKeyContract.resetSession()

        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private func finalizeResult() {
        let fullText = committedText + partialText
        guard !fullText.isEmpty else {
            VoiceKeyContract.setStatus(.idle)
            return
        }
        VoiceKeyContract.setResult(fullText)
        sttProvider?.disconnect()
        sttProvider = nil
    }

    // MARK: - Heartbeat

    private func startHeartbeat() {
        heartbeatTimer?.invalidate()
        VoiceKeyContract.updateHeartbeat()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            VoiceKeyContract.updateHeartbeat()
        }
    }

    func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }
}

// MARK: - AudioCaptureDelegate

extension BackgroundAudioManager: AudioCaptureDelegate {
    func audioCaptureService(_ service: AudioCaptureService, didCapture pcmData: Data) {
        sttProvider?.sendAudio(pcmData)
    }

    func audioCaptureService(_ service: AudioCaptureService, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            VoiceKeyContract.setError("录音错误: \(error.localizedDescription)")
            self?.isRecording = false
        }
    }

    func audioCaptureServiceDidStop(_ service: AudioCaptureService) {}

    func audioCaptureServiceDidDetectSilenceTimeout(_ service: AudioCaptureService) {
        DispatchQueue.main.async { [weak self] in
            self?.stopRecording()
        }
    }
}

// MARK: - STTProviderDelegate

extension BackgroundAudioManager: STTProviderDelegate {
    func sttProviderDidConnect(_ provider: any StreamingSTTProvider) {}

    func sttProviderDidDisconnect(_ provider: any StreamingSTTProvider) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if !self.committedText.isEmpty {
                self.finalizeResult()
            }
        }
    }

    func sttProvider(_ provider: any StreamingSTTProvider, didUpdatePartial text: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.partialText = text
            VoiceKeyContract.setPartialText(self.committedText + text)
        }
    }

    func sttProvider(_ provider: any StreamingSTTProvider, didFinalizePart text: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.committedText += text
            self.partialText = ""

            // For REST providers, this is the final result
            if !SettingsStore.shared.sttEngine.supportsStreaming {
                self.finalizeResult()
            } else {
                VoiceKeyContract.setPartialText(self.committedText)
            }
        }
    }

    func sttProvider(_ provider: any StreamingSTTProvider, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.isRecording = false
            VoiceKeyContract.setError(error.localizedDescription)
        }
    }
}
