//
//  VoiceInputView.swift
//  VoiceKey
//
//  Main app recording UI. Shows when the app is in foreground.
//  Delegates actual recording to BackgroundAudioManager.
//  After first activation, recording can happen entirely in background
//  without this view being visible.
//

import SwiftUI

struct VoiceInputView: View {
    @ObservedObject private var audioManager = BackgroundAudioManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            // Status
            Text(statusMessage)
                .font(.headline)
                .foregroundStyle(statusColor)

            // Transcription display
            ScrollView {
                Text(displayText.isEmpty ? "点击下方按钮开始录音，或返回后从键盘触发" : displayText)
                    .font(.body)
                    .foregroundStyle(displayText.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .frame(maxHeight: .infinity)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Record button
            Button {
                if audioManager.isRecording {
                    VoiceKeyContract.sendCommand(.stopRecording)
                } else {
                    if !audioManager.isActivated {
                        audioManager.activate()
                    }
                    VoiceKeyContract.sendCommand(.startRecording)
                }
            } label: {
                Image(systemName: audioManager.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(audioManager.isRecording ? .red : .blue)
            }

            if audioManager.isActivated {
                Label("后台音频已激活，可返回其他 App 使用键盘录音", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            Text("首次激活后，后续可直接从键盘触发录音，无需切回此界面")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .navigationTitle("语音输入")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var displayText: String {
        let status = VoiceKeyContract.currentStatus()
        switch status {
        case .done:
            return VoiceKeyContract.currentResult()
        case .recording, .processing:
            return VoiceKeyContract.currentPartialText()
        case .error:
            return ""
        case .idle:
            return ""
        }
    }

    private var statusMessage: String {
        let status = VoiceKeyContract.currentStatus()
        switch status {
        case .idle:       return audioManager.isActivated ? "已激活，准备就绪" : "准备就绪"
        case .recording:  return "录音中..."
        case .processing: return "处理中..."
        case .done:       return "识别完成"
        case .error:      return VoiceKeyContract.currentError()
        }
    }

    private var statusColor: Color {
        let status = VoiceKeyContract.currentStatus()
        switch status {
        case .idle:       return .secondary
        case .recording:  return .red
        case .processing: return .orange
        case .done:       return .green
        case .error:      return .red
        }
    }
}

#Preview {
    NavigationStack {
        VoiceInputView()
    }
}
