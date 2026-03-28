//
//  KeyboardViewController.swift
//  VoiceKeyboard
//
//  Created by Peng Chen on 28/3/26.
//
//  Lightweight keyboard controller — no audio/ASR code.
//  Recording is delegated to the main app via URL Scheme.
//  Results are read from App Group UserDefaults.
//
//  Flow:
//    1. User taps mic → open main app via URL Scheme
//    2. Main app records + ASR → writes result to App Group
//    3. Keyboard polls App Group → shows result in DraftCanvas
//    4. User edits/confirms → text inserted into host app
//

import UIKit

final class KeyboardViewController: UIInputViewController {

    // MARK: - Views

    private let draftCanvas  = DraftCanvasView()
    private let candidateBar = CandidateBarView()
    private let keyboardView = KeyboardView()
    private let pinyinEngine = PinyinEngine()

    // MARK: - State

    private var pinyinBuffer = ""
    private var currentLanguageIndex = 0
    private var lastResultTimestamp: TimeInterval = 0

    /// Timer that polls App Group for STT results.
    private var pollTimer: Timer?

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
        if !draftCanvas.isHidden    { h += 80 }
        if !pinyinBuffer.isEmpty    { h += 44 }
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

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        checkForPendingResult()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopPolling()
    }

    // MARK: - UI Setup

    private func setupUI() {
        view.backgroundColor = .systemGroupedBackground

        let h = view.heightAnchor.constraint(equalToConstant: desiredHeight)
        h.priority = .defaultHigh
        h.isActive = true
        heightConstraint = h

        draftCanvas.translatesAutoresizingMaskIntoConstraints = false
        draftCanvas.isHidden = true
        view.addSubview(draftCanvas)

        candidateBar.translatesAutoresizingMaskIntoConstraints = false
        candidateBar.isHidden = true
        view.addSubview(candidateBar)

        keyboardView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(keyboardView)

        NSLayoutConstraint.activate([
            draftCanvas.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            draftCanvas.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            draftCanvas.topAnchor.constraint(equalTo: view.topAnchor, constant: 4),
            draftCanvas.heightAnchor.constraint(equalToConstant: 76),

            candidateBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            candidateBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            candidateBar.topAnchor.constraint(equalTo: draftCanvas.bottomAnchor),
            candidateBar.heightAnchor.constraint(equalToConstant: 44),

            keyboardView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyboardView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keyboardView.topAnchor.constraint(equalTo: candidateBar.bottomAnchor),
            keyboardView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func setupCallbacks() {
        keyboardView.delegate = self

        draftCanvas.onConfirm = { [weak self] text in
            self?.insertDraftText(text)
        }

        draftCanvas.onCancel = { [weak self] in
            self?.hideDraftCanvas()
            VoiceKeyContract.resetSession()
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
        updateLanguageLabel()
    }

    // MARK: - Draft Canvas management

    private func showDraftCanvas() {
        draftCanvas.isHidden = false
        updateHeight()
    }

    private func hideDraftCanvas() {
        draftCanvas.isHidden = true
        draftCanvas.clear()
        stopPolling()
        updateHeight()
    }

    private func insertDraftText(_ text: String) {
        textDocumentProxy.insertText(text)
        hideDraftCanvas()
        VoiceKeyContract.resetSession()
    }

    // MARK: - Recording trigger (URL Scheme)

    private func triggerRecording() {
        guard hasFullAccess else {
            showToast("请在「设置 → 键盘 → VoiceKey」开启完全访问权限")
            return
        }

        let settings = SettingsStore.shared
        guard !settings.activeAPIKey.isEmpty else {
            showToast("请先在 VoiceKey App 中填写 API Key")
            return
        }

        // Show draft canvas in waiting state
        draftCanvas.showWaiting()
        showDraftCanvas()

        // Launch main app via URL Scheme
        guard let url = URL(string: VoiceKeyContract.urlSchemeRecord) else { return }

        // UIApplication.shared is available in keyboard extensions with Full Access
        var responder: UIResponder? = self
        while let r = responder {
            if let app = r as? UIApplication {
                app.open(url, options: [:], completionHandler: nil)
                break
            }
            responder = r.next
        }

        // Start polling for results
        startPolling()
    }

    // MARK: - Polling for results

    private func startPolling() {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkForPendingResult()
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func checkForPendingResult() {
        let status = VoiceKeyContract.currentStatus()

        switch status {
        case .idle:
            break

        case .recording:
            if draftCanvas.isHidden {
                showDraftCanvas()
            }
            draftCanvas.showRecording()

        case .processing:
            draftCanvas.showProcessing()
            // Check for partial text updates
            let partial = VoiceKeyContract.currentPartialText()
            if !partial.isEmpty {
                draftCanvas.showPartial(committed: partial, partial: "")
            }

        case .done:
            let timestamp = VoiceKeyContract.currentTimestamp()
            guard timestamp > lastResultTimestamp else { return }
            lastResultTimestamp = timestamp

            let result = VoiceKeyContract.currentResult()
            if !result.isEmpty {
                draftCanvas.showResult(result)
                if draftCanvas.isHidden {
                    showDraftCanvas()
                }
            }
            stopPolling()

        case .error:
            let errorMsg = VoiceKeyContract.currentError()
            draftCanvas.showError(errorMsg)
            stopPolling()
        }
    }

    // MARK: - Language cycling

    private func cycleLanguage() {
        let langs = SettingsStore.shared.activeLanguages
        guard !langs.isEmpty else { return }
        currentLanguageIndex = (currentLanguageIndex + 1) % langs.count
        let lang = langs[currentLanguageIndex]

        switch lang {
        case .zhCN, .zhYue: keyboardMode = .chinesePinyin
        default:            keyboardMode = .english
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
                textDocumentProxy.insertText(" ")
            }

        case .return:
            if keyboardMode == .chinesePinyin && !pinyinBuffer.isEmpty {
                commitPinyinAsRomaji()
            } else {
                textDocumentProxy.insertText("\n")
            }

        case .delete:
            if keyboardMode == .chinesePinyin && !pinyinBuffer.isEmpty {
                deletePinyinLast()
            } else {
                textDocumentProxy.deleteBackward()
            }

        case .mic:
            triggerRecording()

        case .switchLanguage:
            cycleLanguage()

        case .nextKeyboard:
            advanceToNextInputMode()

        case .edit:
            // Placeholder for M7 — voice command editing
            showToast("编辑模式将在后续版本中推出")

        case .shift, .changeMode:
            break  // handled inside KeyboardView
        }
    }
}
