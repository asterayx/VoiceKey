//
//  KeyboardViewController.swift
//  VoiceKeyboard
//
//  Created by Peng Chen on 28/3/26.
//
//  M2 — full implementation:
//    • QWERTY keyboard (English + Chinese Pinyin) always visible
//    • Mic button toggles Soniox streaming STT
//    • Real-time partial tokens shown in TranscriptionBannerView
//    • Final tokens accumulated and inserted via textDocumentProxy
//    • Pinyin buffer drives CandidateBarView in Chinese mode
//

import UIKit
import AVFoundation

final class KeyboardViewController: UIInputViewController {

    // MARK: - Services

    private let audioService  = AudioCaptureService()
    private var sonioxService: SonioxStreamingService?
    private let pinyinEngine  = PinyinEngine()

    // MARK: - Views

    private let bannerView    = TranscriptionBannerView()
    private let candidateBar  = CandidateBarView()
    private let keyboardView  = KeyboardView()

    // MARK: - State

    private var isRecording  = false
    private var committedSTT = ""      // final tokens accumulated during this session
    private var partialSTT   = ""      // latest non-final token
    private var pinyinBuffer = ""      // typed pinyin in Chinese mode

    private var keyboardMode: KeyboardMode = .english {
        didSet {
            keyboardView.mode = keyboardMode
            updateCandidateBar()
        }
    }

    // MARK: - Height management

    private var heightConstraint: NSLayoutConstraint?

    /// Total height: base keyboard + banner (when recording) + candidate bar (when pinyin active)
    private var desiredHeight: CGFloat {
        var h: CGFloat = 260  // base keyboard
        if isRecording          { h += 56  }
        if !pinyinBuffer.isEmpty { h += 44  }
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

        // Height anchor (priority < required so the system can still override)
        let h = view.heightAnchor.constraint(equalToConstant: desiredHeight)
        h.priority = .defaultHigh
        h.isActive = true
        heightConstraint = h

        // --- Banner (hidden until recording starts) ---
        bannerView.translatesAutoresizingMaskIntoConstraints = false
        bannerView.isHidden = true
        view.addSubview(bannerView)

        // --- Candidate bar (hidden until pinyin buffer non-empty) ---
        candidateBar.translatesAutoresizingMaskIntoConstraints = false
        candidateBar.isHidden = true
        view.addSubview(candidateBar)

        // --- Keyboard ---
        keyboardView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(keyboardView)

        NSLayoutConstraint.activate([
            // Banner pinned to top
            bannerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bannerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bannerView.topAnchor.constraint(equalTo: view.topAnchor),
            bannerView.heightAnchor.constraint(equalToConstant: 56),

            // Candidate bar below banner
            candidateBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            candidateBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            candidateBar.topAnchor.constraint(equalTo: bannerView.bottomAnchor),
            candidateBar.heightAnchor.constraint(equalToConstant: 44),

            // Keyboard fills remainder
            keyboardView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyboardView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keyboardView.topAnchor.constraint(equalTo: candidateBar.bottomAnchor),
            keyboardView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func setupCallbacks() {
        // Keyboard key taps
        keyboardView.delegate = self

        // Banner clear button
        bannerView.onClear = { [weak self] in
            self?.committedSTT = ""
            self?.partialSTT   = ""
        }

        // Candidate selection
        candidateBar.onSelect = { [weak self] character in
            self?.insertCandidate(character)
        }

        // Audio capture
        audioService.delegate = self
    }

    private func applyDefaultLanguage() {
        switch SettingsStore.shared.defaultLanguage {
        case .english: keyboardMode = .english
        case .chinese: keyboardMode = .chinesePinyin
        }
    }

    // MARK: - Recording control

    private func startRecording() {
        guard hasFullAccess else {
            showToast("请在「设置 → 键盘 → VoiceKey」开启完全访问权限")
            return
        }

        let apiKey = SettingsStore.shared.activeAPIKey
        guard !apiKey.isEmpty else {
            showToast("请先在 VoiceKey App 中填写 API Key")
            return
        }

        // Request mic permission at runtime (belt-and-suspenders)
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                if granted {
                    self.beginSession(apiKey: apiKey)
                } else {
                    self.showToast("需要麦克风权限")
                }
            }
        }
    }

    private func beginSession(apiKey: String) {
        committedSTT = ""
        partialSTT   = ""
        bannerView.clear()

        let hints = keyboardMode == .chinesePinyin ? ["zh", "en"] : ["en", "zh"]
        let soniox = SonioxStreamingService(apiKey: apiKey, languageHints: hints)
        soniox.delegate = self
        sonioxService = soniox
        soniox.connect()

        do {
            try audioService.startCapture()
        } catch {
            showToast("麦克风启动失败: \(error.localizedDescription)")
            soniox.disconnect()
            sonioxService = nil
            return
        }

        isRecording = true
        keyboardView.isRecording = true
        setBannerVisible(true)
    }

    private func stopRecording() {
        guard isRecording else { return }
        audioService.stopCapture()
        sonioxService?.finishAudio()
        // Final tokens will arrive via delegate; we disconnect after a short grace period
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.sonioxService?.disconnect()
            self?.sonioxService = nil
        }
        isRecording = false
        keyboardView.isRecording = false
    }

    // MARK: - Text insertion

    /// Insert all accumulated STT text into the active text field and reset.
    private func flushSTTText() {
        let full = committedSTT + partialSTT
        guard !full.isEmpty else { return }
        textDocumentProxy.insertText(full)
        committedSTT = ""
        partialSTT   = ""
        bannerView.clear()
        setBannerVisible(false)
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
        // User pressed space / return without selecting a candidate — insert raw pinyin
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

        case .space:
            if keyboardMode == .chinesePinyin && !pinyinBuffer.isEmpty {
                // Space selects first candidate or commits raw pinyin
                let candidates = pinyinEngine.candidates(for: pinyinBuffer)
                if let first = candidates.first {
                    insertCandidate(first)
                } else {
                    commitPinyinAsRomaji()
                }
            } else {
                // If recording and there's accumulated STT, insert it first
                if isRecording && !committedSTT.isEmpty {
                    flushSTTText()
                }
                textDocumentProxy.insertText(" ")
            }

        case .return:
            if keyboardMode == .chinesePinyin && !pinyinBuffer.isEmpty {
                commitPinyinAsRomaji()
            } else {
                if isRecording { flushSTTText() }
                textDocumentProxy.insertText("\n")
            }

        case .delete:
            if keyboardMode == .chinesePinyin && !pinyinBuffer.isEmpty {
                deletePinyinLast()
            } else {
                textDocumentProxy.deleteBackward()
            }

        case .mic:
            if isRecording {
                stopRecording()
                // Insert accumulated text on stop
                flushSTTText()
            } else {
                startRecording()
            }

        case .switchLanguage:
            keyboardMode = (keyboardMode == .english) ? .chinesePinyin : .english
            pinyinBuffer = ""
            updateCandidateBar()

        case .nextKeyboard:
            advanceToNextInputMode()

        case .shift, .changeMode, .digit:
            break  // shift is handled inside KeyboardView itself
        }
    }
}

// MARK: - AudioCaptureDelegate

extension KeyboardViewController: AudioCaptureDelegate {
    func audioCaptureService(_ service: AudioCaptureService, didCapture pcmData: Data) {
        sonioxService?.sendAudio(pcmData)
    }

    func audioCaptureService(_ service: AudioCaptureService, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.showToast("录音错误: \(error.localizedDescription)")
            self?.stopRecording()
        }
    }

    func audioCaptureServiceDidStop(_ service: AudioCaptureService) {
        // No-op; stopRecording() already handles state
    }
}

// MARK: - SonioxStreamingDelegate

extension KeyboardViewController: SonioxStreamingDelegate {

    func sonioxServiceDidConnect(_ service: SonioxStreamingService) {
        // Connected — audio is already flowing from startCapture()
    }

    func sonioxServiceDidDisconnect(_ service: SonioxStreamingService) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.isRecording {
                // Unexpected disconnect
                self.stopRecording()
                self.showToast("语音识别连接断开")
            }
        }
    }

    func sonioxService(_ service: SonioxStreamingService, didUpdatePartial text: String) {
        partialSTT = text
        bannerView.update(committed: committedSTT, partial: partialSTT)
    }

    func sonioxService(_ service: SonioxStreamingService, didFinalizePart text: String) {
        committedSTT += text
        partialSTT = ""
        bannerView.update(committed: committedSTT, partial: "")
    }

    func sonioxService(_ service: SonioxStreamingService, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.showToast("Soniox 错误: \(error.localizedDescription)")
            self?.stopRecording()
        }
    }
}
