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

import AVFoundation
import Combine
import SwiftUI

@main
struct VoiceKeyApp: App {
    @StateObject private var audioManager = BackgroundAudioManager.shared
    @State private var selectedTab = 0

    var body: some Scene {
        WindowGroup {
            TabView(selection: $selectedTab) {
                Tab("录音", systemImage: "mic.circle.fill", value: 0) {
                    NavigationStack {
                        VoiceInputView()
                    }
                }
                Tab("设置", systemImage: "gearshape", value: 1) {
                    NavigationStack {
                        ContentView()
                    }
                }
            }
            .onOpenURL { url in
                handleURL(url)
            }
            .onAppear {
                audioManager.activate()
                audioManager.startListeningForCommands()
            }
        }
    }

    private func handleURL(_ url: URL) {
        guard url.scheme == "voicekey" else { return }

        switch url.host {
        case "activate", "record", "command":
            audioManager.activate()
            selectedTab = 0
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
    @Published var isProcessing = false

    /// Published text for VoiceInputView to observe reactively.
    /// Updated on every partial/final token from STT.
    @Published var displayText = ""

    private let audioService = AudioCaptureService()
    private var sttProvider: (any StreamingSTTProvider)?
    private var heartbeatTimer: Timer?
    private var lastCommandTimestamp: TimeInterval = 0

    // STT accumulation
    private var committedText = ""
    private var partialText = ""
    private var hasFinalized = false

    /// Tracks whether we're in an error state — prevents finalizeResult from
    /// overwriting the error with idle/done status.
    private var isInErrorState = false

    /// After finishAudio(), this timer fires when no new tokens arrive for 1.5s.
    /// Resets on each incoming token so we don't cut off slow-arriving results.
    private var drainTimer: Timer?

    private init() {}

    // MARK: - Activation

    /// Activate background audio session. Called from URL Scheme handler.
    func activate() {
        guard !isActivated else { return }

        // Set up audio session once and keep it alive for background residency.
        activateAudioSession()

        // Listen for audio session interruptions (phone calls, Siri, etc.)
        // Re-activate the session when the interruption ends.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )

        isActivated = true

        // Start heartbeat so keyboard knows we're alive
        startHeartbeat()

        // Reset session state
        VoiceKeyContract.resetSession()
    }

    private func activateAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default,
                                    options: [.defaultToSpeaker, .allowBluetoothA2DP])
            try session.setActive(true)
        } catch {
            print("[VoiceKey] Audio session activation failed: \(error)")
        }
    }

    @objc private func handleAudioInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }

        switch type {
        case .began:
            // System interrupted our session (phone call, Siri, etc.)
            // If recording, stop gracefully.
            if isRecording {
                stopRecording()
            }
        case .ended:
            // Interruption ended — re-activate session for background residency.
            let options = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            if AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) {
                activateAudioSession()
            } else {
                // Re-activate anyway — we need it for keyboard-triggered recording.
                activateAudioSession()
            }
        @unknown default:
            break
        }
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

    func startRecording() {
        guard !isRecording else { return }

        let settings = SettingsStore.shared
        let apiKey = settings.activeAPIKey

        guard !apiKey.isEmpty else {
            VoiceKeyContract.setError("API Key 未配置，请打开 VoiceKey App 设置")
            return
        }

        // Ensure audio session is active
        if !isActivated { activate() }

        // Check microphone permission
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            performStartRecording(settings: settings, apiKey: apiKey)
        case .undetermined:
            AVAudioApplication.requestRecordPermission { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.performStartRecording(settings: settings, apiKey: apiKey)
                    } else {
                        VoiceKeyContract.setError("麦克风权限被拒绝，请在「设置」中开启")
                    }
                }
            }
        case .denied:
            VoiceKeyContract.setError("麦克风权限被拒绝，请在「设置 → VoiceKey」中开启")
        @unknown default:
            VoiceKeyContract.setError("无法确定麦克风权限状态")
        }
    }

    private func performStartRecording(settings: SettingsStore, apiKey: String) {
        // Clean up any lingering provider from a previous session to prevent
        // stale delegate callbacks interfering with this new session.
        if let old = sttProvider {
            old.delegate = nil
            old.disconnect()
            sttProvider = nil
        }

        drainTimer?.invalidate()
        drainTimer = nil
        committedText = ""
        partialText = ""
        hasFinalized = false
        isInErrorState = false
        isProcessing = false
        displayText = ""

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

        // Start audio capture immediately, then connect WebSocket.
        // Frames sent before WebSocket is ready are dropped (sendAudio guards
        // on isConnected). Losing a few frames at the start is acceptable.
        // Starting audio first keeps the app alive in background via
        // UIBackgroundModes:audio while the WebSocket handshake completes.
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
        provider.connect()

        // Keep screen on while recording in foreground
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = true
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        isProcessing = true

        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = false
        }

        // IMPORTANT: finish STT first (sends end-of-audio signal over WebSocket),
        // THEN stop audio capture. Reversing this order kills the WebSocket
        // before finishAudio can send its closing frame.
        if SettingsStore.shared.sttEngine.supportsStreaming {
            sttProvider?.finishAudio()
            audioService.stopCapture()
            VoiceKeyContract.setStatus(.processing)
            // Start drain timer: finalize once no new tokens arrive for 1.5s.
            // If Soniox closes the WebSocket, sttProviderDidDisconnect finalizes
            // immediately. The drain timer handles the case where Soniox keeps
            // the connection open after delivering all tokens.
            startDrainTimer()
        } else {
            audioService.stopCapture()
            sttProvider?.finishAudio()
            VoiceKeyContract.setStatus(.processing)
        }
    }

    private func cancelRecording() {
        drainTimer?.invalidate()
        drainTimer = nil
        audioService.stopCapture()
        sttProvider?.delegate = nil
        sttProvider?.disconnect()
        sttProvider = nil
        isRecording = false
        isProcessing = false
        committedText = ""
        partialText = ""
        displayText = ""
        VoiceKeyContract.resetSession()

        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private func finalizeResult() {
        drainTimer?.invalidate()
        drainTimer = nil
        // Don't overwrite error state — the error message is more useful than idle/done.
        guard !hasFinalized, !isInErrorState else { return }
        hasFinalized = true
        isProcessing = false

        let fullText = committedText + partialText
        guard !fullText.isEmpty else {
            VoiceKeyContract.setStatus(.idle)
            return
        }
        VoiceKeyContract.setResult(fullText)
        displayText = fullText
        sttProvider?.delegate = nil
        sttProvider?.disconnect()
        sttProvider = nil
    }

    /// Start or restart the drain timer. Each incoming token resets the timer.
    /// When 1.5s passes with no new tokens, we assume Soniox is done and finalize.
    private func startDrainTimer() {
        drainTimer?.invalidate()
        drainTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            self?.drainTimer = nil
            self?.finalizeResult()
        }
    }

    /// Clean up everything after an error. Stops audio, nils provider, sets error state.
    private func handleRecordingError(_ message: String) {
        drainTimer?.invalidate()
        drainTimer = nil
        isInErrorState = true
        isRecording = false
        isProcessing = false
        audioService.stopCapture()
        sttProvider?.delegate = nil
        sttProvider?.disconnect()
        sttProvider = nil
        VoiceKeyContract.setError(message)

        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = false
        }
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
        // Audio tap fires on the audio render thread.
        // Dispatch to main for thread-safe access to sttProvider/isConnected.
        // sendAudio internally guards on isConnected — frames before WebSocket
        // connects are silently dropped (a few frames lost is acceptable).
        DispatchQueue.main.async { [weak self] in
            self?.sttProvider?.sendAudio(pcmData)
        }
    }

    func audioCaptureService(_ service: AudioCaptureService, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.handleRecordingError("录音错误: \(error.localizedDescription)")
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
    func sttProviderDidConnect(_ provider: any StreamingSTTProvider) {
        // WebSocket ready. Audio is already flowing via audioCaptureService delegate.
    }

    func sttProviderDidDisconnect(_ provider: any StreamingSTTProvider) {
        // Clean WebSocket close — Soniox finished sending all tokens.
        DispatchQueue.main.async { [weak self] in
            self?.finalizeResult()
        }
    }

    func sttProvider(_ provider: any StreamingSTTProvider, didUpdatePartial text: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.partialText = text
            let combined = self.committedText + text
            VoiceKeyContract.setPartialText(combined)
            self.displayText = combined
            // Reset drain timer — more tokens are still arriving
            if self.drainTimer != nil { self.startDrainTimer() }
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
                self.displayText = self.committedText
                // Reset drain timer — more tokens are still arriving
                if self.drainTimer != nil { self.startDrainTimer() }
            }
        }
    }

    func sttProvider(_ provider: any StreamingSTTProvider, didFailWithError error: Error) {
        // Full cleanup: stop audio, nil provider, show error.
        // handleError in SonioxStreamingService already called tearDown(), so
        // the provider is in a dead state — just clean up our side.
        DispatchQueue.main.async { [weak self] in
            self?.handleRecordingError(error.localizedDescription)
        }
    }
}
