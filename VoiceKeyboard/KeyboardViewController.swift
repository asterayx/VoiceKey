//
//  KeyboardViewController.swift
//  VoiceKeyboard
//
//  Created by Peng Chen on 28/3/26.
//
//  M3–M5 implementation:
//    • Provider-agnostic STT via StreamingSTTProvider protocol
//    • Multi-provider support (Soniox, Groq, Cerebras) via STTProviderFactory
//    • Silence detection with configurable timeout
//    • Number/symbol keyboard modes
//    • Three-state banner (recording / processing / error)
//    • Multi-language support with cycling
//    • Edit button placeholder for M7
//

import UIKit
import AVFoundation

// MARK: - Recording state machine

private enum RecordingState {
    case idle
    case recording
    case processing   // waiting for REST-based provider to return results
}

final class KeyboardViewController: UIInputViewController {

    // MARK: - Services

    private let audioService = AudioCaptureService()
    private var sttProvider: (any StreamingSTTProvider)?
    private let pinyinEngine = PinyinEngine()

    // MARK: - Views

    private let bannerView   = TranscriptionBannerView()
    private let candidateBar = CandidateBarView()
    private let keyboardView = KeyboardView()

    // MARK: - State

    private var recordingState: RecordingState = .idle
    private var committedSTT = ""
    private var partialSTT   = ""
    private var pinyinBuffer = ""

    /// Index into activeLanguages for cycling
    private var currentLanguageIndex = 0

    private var keyboardMode: KeyboardMode = .english {
        didSet {
            keyboardView.mode = keyboardMode
            updateLanguageLabel()
            updateCandidateBar()
        }
    }

    // MARK: - Height management

    private var heightConstraint: NSLayoutConstraint?

    private var desiredHeight: CGFloat {
        var h: CGFloat = 260
        if recordingState != .idle    { h += 56 }
        if !pinyinBuffer.isEmpty      { h += 44 }
        return h
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupCallbacks()
        applyDefaultLanguage()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        keyboardView.needsInputModeSwitchKey = needsInputModeSwitchKey
    }

    // MARK: - UI Setup

    private func setupUI() {
        view.backgroundColor = .systemGroupedBackground

        let h = view.heightAnchor.constraint(equalToConstant: desiredHeight)
        h.priority = .defaultHigh
        h.isActive = true
        heightConstraint = h

        bannerView.translatesAutoresizingMaskIntoConstraints = false
        bannerView.isHidden = true
        view.addSubview(bannerView)

        candidateBar.translatesAutoresizingMaskIntoConstraints = false
        candidateBar.isHidden = true
        view.addSubview(candidateBar)

        keyboardView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(keyboardView)

        NSLayoutConstraint.activate([
            bannerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bannerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bannerView.topAnchor.constraint(equalTo: view.topAnchor),
            bannerView.heightAnchor.constraint(equalToConstant: 56),

            candidateBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            candidateBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            candidateBar.topAnchor.constraint(equalTo: bannerView.bottomAnchor),
            candidateBar.heightAnchor.constraint(equalToConstant: 44),

            keyboardView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyboardView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keyboardView.topAnchor.constraint(equalTo: candidateBar.bottomAnchor),
            keyboardView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func setupCallbacks() {
        keyboardView.delegate = self
        audioService.delegate = self

        bannerView.onClear = { [weak self] in
            self?.committedSTT = ""
            self?.partialSTT   = ""
        }

        bannerView.onRetry = { [weak self] in
            self?.startRecording()
        }

        bannerView.onCancel = { [weak self] in
            self?.cancelRecording()
        }

        candidateBar.onSelect = { [weak self] character in
            self?.insertCandidate(character)
        }
    }

    private func applyDefaultLanguage() {
        let settings = SettingsStore.shared
        let langs = settings.activeLanguages
        currentLanguageIndex = 0

        if let first = langs.first {
            switch first {
            case .zhCN, .zhYue: keyboardMode = .chinesePinyin
            default:            keyboardMode = .english
            }
        }

        // Configure silence detector from settings
        audioService.silenceDetector.timeoutSeconds = settings.silenceTimeoutSeconds

        updateLanguageLabel()
    }

    // MARK: - Language cycling

    private func cycleLanguage() {
        let langs = SettingsStore.shared.activeLanguages
        guard !langs.isEmpty else { return }
        currentLanguageIndex = (currentLanguageIndex + 1) % langs.count
        let lang = langs[currentLanguageIndex]

        switch lang {
        case .zhCN, .zhYue:
            keyboardMode = .chinesePinyin
        default:
            keyboardMode = .english
        }
        pinyinBuffer = ""
        updateCandidateBar()
    }

    private func updateLanguageLabel() {
        let langs = SettingsStore.shared.activeLanguages
        if currentLanguageIndex < langs.count {
            keyboardView.currentLanguageLabel = langs[currentLanguageIndex].shortLabel
        } else {
            keyboardView.currentLanguageLabel = "EN"
        }
    }

    private var currentLanguage: RecognitionLanguage {
        let langs = SettingsStore.shared.activeLanguages
        guard currentLanguageIndex < langs.count else { return .en }
        return langs[currentLanguageIndex]
    }

    // MARK: - Recording control

    private func startRecording() {
        guard hasFullAccess else {
            showToast("请在「设置 → 键盘 → VoiceKey」开启完全访问权限")
            return
        }

        let settings = SettingsStore.shared
        let apiKey = settings.activeAPIKey
        guard !apiKey.isEmpty else {
            showToast("请先在 VoiceKey App 中填写 API Key")
            return
        }

        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                if granted {
                    self.beginSession(settings: settings, apiKey: apiKey)
                } else {
                    self.showToast("需要麦克风权限")
                }
            }
        }
    }

    private func beginSession(settings: SettingsStore, apiKey: String) {
        committedSTT = ""
        partialSTT   = ""
        bannerView.clear()
        bannerView.setState(.recording)

        // Configure silence detector
        audioService.silenceDetector.timeoutSeconds = settings.silenceTimeoutSeconds

        // Create provider via factory
        let provider = STTProviderFactory.makeProvider(
            engine: settings.sttEngine,
            apiKey: apiKey,
            languages: settings.activeLanguages,
            model: settings.sttModel.isEmpty ? nil : settings.sttModel
        )

        guard let provider else {
            showToast("不支持的语音识别引擎: \(settings.sttEngine.displayName)")
            return
        }

        provider.delegate = self
        sttProvider = provider
        provider.connect()

        do {
            try audioService.startCapture()
        } catch {
            showToast("麦克风启动失败: \(error.localizedDescription)")
            provider.disconnect()
            sttProvider = nil
            return
        }

        recordingState = .recording
        keyboardView.micState = .recording
        setBannerVisible(true)
    }

    private func stopRecording() {
        guard recordingState == .recording else { return }
        audioService.stopCapture()

        let settings = SettingsStore.shared

        if settings.sttEngine.supportsStreaming {
            // Streaming provider: signal end-of-audio, wait for final tokens
            sttProvider?.finishAudio()
            recordingState = .idle
            keyboardView.micState = .idle
            // Grace period for final tokens
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.sttProvider?.disconnect()
                self?.sttProvider = nil
            }
        } else {
            // REST provider: show processing state while waiting for response
            sttProvider?.finishAudio()
            recordingState = .processing
            keyboardView.micState = .processing
            bannerView.setState(.processing)
            // Start progress animation
            animateProgress()
        }
    }

    private func cancelRecording() {
        audioService.stopCapture()
        sttProvider?.disconnect()
        sttProvider = nil
        recordingState = .idle
        keyboardView.micState = .idle
        committedSTT = ""
        partialSTT = ""
        bannerView.clear()
        setBannerVisible(false)
    }

    /// Animated progress bar for REST-based providers.
    private func animateProgress() {
        // Simulate progress over ~10 seconds
        var progress: Float = 0
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            guard let self, self.recordingState == .processing else {
                timer.invalidate()
                return
            }
            progress = min(progress + 0.05, 0.95)  // never reaches 100% until result arrives
            self.bannerView.setProgress(progress)
        }
    }

    // MARK: - Text insertion

    private func flushSTTText() {
        let full = committedSTT + partialSTT
        guard !full.isEmpty else { return }
        textDocumentProxy.insertText(full)
        committedSTT = ""
        partialSTT   = ""
        bannerView.clear()
        setBannerVisible(false)
        recordingState = .idle
        keyboardView.micState = .idle
    }

    // MARK: - Pinyin handling

    private func appendPinyin(_ letter: String) {
        pinyinBuffer += letter.lowercased()
        updateCandidateBar()
    }

    private func deletePinyinLast() {
        guard !pinyinBuffer.isEmpty else { return }
        pinyinBuffer.removeLast()
        updateCandidateBar()
    }

    private func insertCandidate(_ character: String) {
        textDocumentProxy.insertText(character)
        pinyinBuffer = ""
        updateCandidateBar()
    }

    private func commitPinyinAsRomaji() {
        guard !pinyinBuffer.isEmpty else { return }
        textDocumentProxy.insertText(pinyinBuffer)
        pinyinBuffer = ""
        updateCandidateBar()
    }

    private func updateCandidateBar() {
        let showBar = keyboardMode == .chinesePinyin && !pinyinBuffer.isEmpty
        candidateBar.isHidden = !showBar
        if showBar {
            let candidates = pinyinEngine.candidates(for: pinyinBuffer)
            candidateBar.setCandidates(candidates, pinyin: pinyinBuffer)
        }
        updateHeight()
    }

    // MARK: - Layout helpers

    private func setBannerVisible(_ visible: Bool) {
        UIView.animate(withDuration: 0.2) {
            self.bannerView.isHidden = !visible
            self.updateHeight()
            self.view.layoutIfNeeded()
        }
    }

    private func updateHeight() {
        heightConstraint?.constant = desiredHeight
    }

    // MARK: - Toast

    private func showToast(_ message: String) {
        let label = UILabel()
        label.text = message
        label.font = .systemFont(ofSize: 13)
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.75)
        label.textAlignment = .center
        label.layer.cornerRadius = 8
        label.layer.masksToBounds = true
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
            label.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -32),
        ])

        UIView.animate(withDuration: 0.2, delay: 2.0, options: []) {
            label.alpha = 0
        } completion: { _ in
            label.removeFromSuperview()
        }
    }
}

// MARK: - KeyboardViewDelegate

extension KeyboardViewController: KeyboardViewDelegate {
    func keyboardView(_ view: KeyboardView, didTap key: KeyboardKey) {
        switch key {

        case .letter(let char):
            if keyboardMode == .chinesePinyin {
                appendPinyin(char)
            } else {
                textDocumentProxy.insertText(char)
            }

        case .digit(let d):
            textDocumentProxy.insertText(d)

        case .symbol(let s):
            textDocumentProxy.insertText(s)

        case .space:
            if keyboardMode == .chinesePinyin && !pinyinBuffer.isEmpty {
                let candidates = pinyinEngine.candidates(for: pinyinBuffer)
                if let first = candidates.first {
                    insertCandidate(first)
                } else {
                    commitPinyinAsRomaji()
                }
            } else {
                if recordingState == .recording && !committedSTT.isEmpty {
                    flushSTTText()
                }
                textDocumentProxy.insertText(" ")
            }

        case .return:
            if keyboardMode == .chinesePinyin && !pinyinBuffer.isEmpty {
                commitPinyinAsRomaji()
            } else {
                if recordingState == .recording { flushSTTText() }
                textDocumentProxy.insertText("\n")
            }

        case .delete:
            if keyboardMode == .chinesePinyin && !pinyinBuffer.isEmpty {
                deletePinyinLast()
            } else {
                textDocumentProxy.deleteBackward()
            }

        case .mic:
            switch recordingState {
            case .idle:
                startRecording()
            case .recording:
                stopRecording()
                // For streaming providers, flush text immediately
                if SettingsStore.shared.sttEngine.supportsStreaming {
                    flushSTTText()
                }
            case .processing:
                // Already processing — ignore or cancel
                break
            }

        case .switchLanguage:
            cycleLanguage()

        case .nextKeyboard:
            advanceToNextInputMode()

        case .edit:
            // Placeholder for M7 — show toast for now
            showToast("编辑模式将在后续版本中推出")

        case .shift, .changeMode:
            break  // handled inside KeyboardView
        }
    }
}

// MARK: - AudioCaptureDelegate

extension KeyboardViewController: AudioCaptureDelegate {
    func audioCaptureService(_ service: AudioCaptureService, didCapture pcmData: Data) {
        sttProvider?.sendAudio(pcmData)
    }

    func audioCaptureService(_ service: AudioCaptureService, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.showToast("录音错误: \(error.localizedDescription)")
            self?.stopRecording()
        }
    }

    func audioCaptureServiceDidStop(_ service: AudioCaptureService) {
        // No-op
    }

    func audioCaptureServiceDidDetectSilenceTimeout(_ service: AudioCaptureService) {
        // Auto-stop on silence
        DispatchQueue.main.async { [weak self] in
            guard let self, self.recordingState == .recording else { return }
            self.stopRecording()
            if SettingsStore.shared.sttEngine.supportsStreaming {
                self.flushSTTText()
            }
        }
    }
}

// MARK: - STTProviderDelegate

extension KeyboardViewController: STTProviderDelegate {

    func sttProviderDidConnect(_ provider: any StreamingSTTProvider) {
        // Connected — audio is already flowing
    }

    func sttProviderDidDisconnect(_ provider: any StreamingSTTProvider) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            if self.recordingState == .processing {
                // REST provider finished — insert text
                self.flushSTTText()
            } else if self.recordingState == .recording {
                // Unexpected disconnect during recording
                self.recordingState = .idle
                self.keyboardView.micState = .idle
                self.showToast("语音识别连接断开")
            }
        }
    }

    func sttProvider(_ provider: any StreamingSTTProvider, didUpdatePartial text: String) {
        partialSTT = text
        bannerView.update(committed: committedSTT, partial: partialSTT)
    }

    func sttProvider(_ provider: any StreamingSTTProvider, didFinalizePart text: String) {
        committedSTT += text
        partialSTT = ""
        bannerView.update(committed: committedSTT, partial: "")
    }

    func sttProvider(_ provider: any StreamingSTTProvider, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.recordingState == .processing {
                // REST provider failed — show error with retry
                self.bannerView.setState(.error(error.localizedDescription))
                self.keyboardView.micState = .idle
                self.recordingState = .idle
            } else {
                self.showToast("语音识别错误: \(error.localizedDescription)")
                self.stopRecording()
            }
        }
    }
}
