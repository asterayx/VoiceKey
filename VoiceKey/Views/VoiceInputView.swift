//
//  VoiceInputView.swift
//  VoiceKey
//
//  Main app recording UI. Launched via URL Scheme from the keyboard extension.
//  Handles audio capture, STT processing, and writes results to App Group.
//

import SwiftUI
import AVFoundation

struct VoiceInputView: View {
    @StateObject private var viewModel = VoiceInputViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            // Status
            Text(viewModel.statusMessage)
                .font(.headline)
                .foregroundStyle(viewModel.statusColor)

            // Transcription display
            ScrollView {
                Text(viewModel.displayText.isEmpty ? "点击下方按钮开始录音" : viewModel.displayText)
                    .font(.body)
                    .foregroundStyle(viewModel.displayText.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .frame(maxHeight: .infinity)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Record button
            Button {
                viewModel.toggleRecording()
            } label: {
                Image(systemName: viewModel.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(viewModel.isRecording ? .red : .blue)
            }

            // Done button (visible after result)
            if viewModel.hasResult {
                Button("完成并返回") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }

            Text("录音完成后请切回原应用，键盘将自动获取结果")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .navigationTitle("语音输入")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.autoStartIfNeeded()
        }
        .onDisappear {
            viewModel.cleanup()
        }
    }
}

// MARK: - ViewModel

final class VoiceInputViewModel: ObservableObject {

    @Published var isRecording = false
    @Published var statusMessage = "准备就绪"
    @Published var displayText = ""
    @Published var hasResult = false

    var statusColor: Color {
        if isRecording { return .red }
        if hasResult { return .green }
        return .secondary
    }

    private let audioService = AudioCaptureService()
    private var sttProvider: (any StreamingSTTProvider)?
    private var committedText = ""
    private var partialText = ""
    private var autoStarted = false

    func autoStartIfNeeded() {
        guard !autoStarted else { return }
        autoStarted = true

        // If launched from keyboard via URL Scheme, auto-start recording
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.startRecording()
        }
    }

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    func cleanup() {
        if isRecording {
            stopRecording()
        }
        sttProvider?.disconnect()
        sttProvider = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func startRecording() {
        let settings = SettingsStore.shared
        let apiKey = settings.activeAPIKey
        guard !apiKey.isEmpty else {
            statusMessage = "请先在设置中填写 API Key"
            return
        }

        AVAudioApplication.requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                if granted {
                    self.beginSession(settings: settings, apiKey: apiKey)
                } else {
                    self.statusMessage = "需要麦克风权限"
                }
            }
        }
    }

    private func beginSession(settings: SettingsStore, apiKey: String) {
        committedText = ""
        partialText = ""
        displayText = ""
        hasResult = false

        // Reset shared state
        VoiceKeyContract.resetSession()
        VoiceKeyContract.setStatus(.recording)

        // Prevent screen dimming during recording
        UIApplication.shared.isIdleTimerDisabled = true

        // Configure silence detector
        audioService.silenceDetector.timeoutSeconds = settings.silenceTimeoutSeconds

        // Create STT provider
        let provider = STTProviderFactory.makeProvider(
            engine: settings.sttEngine,
            apiKey: apiKey,
            languages: settings.activeLanguages,
            model: settings.sttModel.isEmpty ? nil : settings.sttModel
        )

        guard let provider else {
            statusMessage = "不支持的引擎: \(settings.sttEngine.displayName)"
            return
        }

        provider.delegate = self
        sttProvider = provider
        provider.connect()

        audioService.delegate = self

        do {
            try audioService.startCapture()
        } catch {
            statusMessage = "麦克风启动失败: \(error.localizedDescription)"
            provider.disconnect()
            sttProvider = nil
            return
        }

        isRecording = true
        statusMessage = "录音中..."
    }

    private func stopRecording() {
        guard isRecording else { return }
        audioService.stopCapture()
        isRecording = false
        UIApplication.shared.isIdleTimerDisabled = false

        let settings = SettingsStore.shared
        if settings.sttEngine.supportsStreaming {
            sttProvider?.finishAudio()
            statusMessage = "等待最终结果..."
            VoiceKeyContract.setStatus(.processing)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.finalizeResult()
            }
        } else {
            sttProvider?.finishAudio()
            statusMessage = "处理中..."
            VoiceKeyContract.setStatus(.processing)
        }
    }

    private func finalizeResult() {
        let fullText = committedText + partialText
        guard !fullText.isEmpty else {
            statusMessage = "未检测到语音"
            VoiceKeyContract.setStatus(.idle)
            return
        }

        displayText = fullText
        hasResult = true
        statusMessage = "识别完成"
        VoiceKeyContract.setResult(fullText)

        sttProvider?.disconnect()
        sttProvider = nil
    }
}

// MARK: - AudioCaptureDelegate

extension VoiceInputViewModel: AudioCaptureDelegate {
    func audioCaptureService(_ service: AudioCaptureService, didCapture pcmData: Data) {
        sttProvider?.sendAudio(pcmData)
    }

    func audioCaptureService(_ service: AudioCaptureService, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.statusMessage = "录音错误: \(error.localizedDescription)"
            self?.stopRecording()
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

extension VoiceInputViewModel: STTProviderDelegate {
    func sttProviderDidConnect(_ provider: any StreamingSTTProvider) {}

    func sttProviderDidDisconnect(_ provider: any StreamingSTTProvider) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if !self.hasResult && !self.committedText.isEmpty {
                self.finalizeResult()
            }
        }
    }

    func sttProvider(_ provider: any StreamingSTTProvider, didUpdatePartial text: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.partialText = text
            self.displayText = self.committedText + text
            VoiceKeyContract.setPartialText(self.displayText)
        }
    }

    func sttProvider(_ provider: any StreamingSTTProvider, didFinalizePart text: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.committedText += text
            self.partialText = ""
            self.displayText = self.committedText

            // For REST providers, this is the final result
            if !SettingsStore.shared.sttEngine.supportsStreaming {
                self.finalizeResult()
            } else {
                VoiceKeyContract.setPartialText(self.displayText)
            }
        }
    }

    func sttProvider(_ provider: any StreamingSTTProvider, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.statusMessage = "识别错误: \(error.localizedDescription)"
            self?.isRecording = false
            VoiceKeyContract.setError(error.localizedDescription)
        }
    }
}

#Preview {
    NavigationStack {
        VoiceInputView()
    }
}
