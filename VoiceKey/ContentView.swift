//
//  ContentView.swift
//  VoiceKey
//
//  Created by Peng Chen on 28/3/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var settings = SettingsStore.shared
    @State private var apiTestState: APITestState = .idle

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Engine Selection
                Section("Speech-to-Text Engine") {
                    Picker("Engine", selection: $settings.sttEngine) {
                        ForEach(STTEngine.allCases) { engine in
                            Text(engine.displayName).tag(engine)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: settings.sttEngine) { _, newEngine in
                        // Set default model when switching engine
                        if settings.sttModel.isEmpty || !newEngine.availableModels.contains(settings.sttModel) {
                            settings.sttModel = newEngine.defaultModel
                        }
                        apiTestState = .idle
                    }

                    // Model picker
                    Picker("Model", selection: $settings.sttModel) {
                        ForEach(settings.sttEngine.availableModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .pickerStyle(.menu)

                    if !settings.sttEngine.supportsStreaming {
                        Label("此引擎不支持实时流式识别，录音结束后统一处理",
                              systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // MARK: - API Keys
                apiKeySection(title: "Soniox", key: $settings.sonioxAPIKey,
                              hint: "console.soniox.com", engine: .soniox)
                apiKeySection(title: "Groq", key: $settings.groqAPIKey,
                              hint: "console.groq.com", engine: .groq)
                apiKeySection(title: "Cerebras", key: $settings.cerebrasAPIKey,
                              hint: "cloud.cerebras.ai", engine: .cerebras)
                apiKeySection(title: "Deepgram", key: $settings.deepgramAPIKey,
                              hint: "console.deepgram.com", engine: .deepgram)

                // MARK: - Languages
                Section {
                    ForEach(RecognitionLanguage.allCases) { lang in
                        Toggle(lang.displayName, isOn: languageBinding(for: lang))
                    }
                } header: {
                    Text("Recognition Languages")
                } footer: {
                    let names = settings.activeLanguages.map(\.displayName).joined(separator: " > ")
                    Text("Priority: \(names.isEmpty ? "None" : names)")
                }

                // MARK: - Recording
                Section("Recording") {
                    HStack {
                        Text("Silence Timeout")
                        Spacer()
                        Text("\(settings.silenceTimeoutSeconds, specifier: "%.0f")s")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.silenceTimeoutSeconds, in: 1...10, step: 1)
                }

                // MARK: - Status
                Section("Status") {
                    statusRow("Active Engine", value: settings.sttEngine.displayName)
                    statusRow("Languages",
                              value: settings.activeLanguages.map(\.shortLabel).joined(separator: ", "))

                    HStack {
                        Text("API Key")
                        Spacer()
                        Text(settings.activeAPIKey.isEmpty ? "Not set" : "Configured")
                            .foregroundStyle(settings.activeAPIKey.isEmpty ? .red : .green)
                    }
                }

                // MARK: - Help
                Section {
                    Text("Open Settings → Keyboard → Keyboards → Add New Keyboard → VoiceKey to enable the keyboard extension.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("VoiceKey")
        }
    }

    // MARK: - Helpers

    private func apiKeySection(title: String, key: Binding<String>,
                                hint: String, engine: STTEngine) -> some View {
        Section {
            SecureField("\(title) API Key", text: key)
                .textContentType(.password)
                .autocorrectionDisabled()
                .onChange(of: key.wrappedValue) { _, _ in
                    if settings.sttEngine == engine { apiTestState = .idle }
                }

            if settings.sttEngine == engine && !key.wrappedValue.isEmpty {
                Button {
                    testAPIKey(engine: engine, apiKey: key.wrappedValue)
                } label: {
                    HStack {
                        switch apiTestState {
                        case .idle:
                            Label("测试 API Key", systemImage: "play.circle")
                        case .testing:
                            ProgressView()
                                .controlSize(.small)
                            Text("测试中...")
                        case .success:
                            Label("连接成功", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        case .failure(let msg):
                            Label(msg, systemImage: "xmark.circle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                }
                .disabled(apiTestState == .testing)
            }
        } header: {
            HStack {
                Text(title)
                if settings.sttEngine == engine {
                    Text("(Active)")
                        .foregroundStyle(.blue)
                        .font(.caption)
                }
            }
        } footer: {
            Text("Get your key at \(hint)")
        }
    }

    private func statusRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }

    /// Two-way binding: toggling adds/removes language from activeLanguages.
    private func languageBinding(for lang: RecognitionLanguage) -> Binding<Bool> {
        Binding(
            get: { settings.activeLanguages.contains(lang) },
            set: { isOn in
                if isOn {
                    if !settings.activeLanguages.contains(lang) {
                        settings.activeLanguages.append(lang)
                    }
                } else {
                    settings.activeLanguages.removeAll { $0 == lang }
                }
            }
        )
    }
}

// MARK: - API Key Test

enum APITestState: Equatable {
    case idle
    case testing
    case success
    case failure(String)
}

extension ContentView {

    func testAPIKey(engine: STTEngine, apiKey: String) {
        apiTestState = .testing

        switch engine {
        case .soniox:
            testSonioxKey(apiKey: apiKey)
        case .groq:
            testWhisperKey(apiKey: apiKey, endpoint: "https://api.groq.com/openai/v1/models")
        case .cerebras:
            testWhisperKey(apiKey: apiKey, endpoint: "https://api.cerebras.ai/v1/models")
        case .deepgram:
            testWhisperKey(apiKey: apiKey, endpoint: "https://api.deepgram.com/v1/projects")
        }
    }

    /// Test Soniox by opening a WebSocket and sending config.
    private func testSonioxKey(apiKey: String) {
        let url = URL(string: "wss://api.soniox.com/transcribe-websocket")!
        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: url)
        task.resume()

        let config: [String: Any] = [
            "api_key": apiKey,
            "model": settings.sttModel.isEmpty ? "soniox_multilingual" : settings.sttModel,
            "include_nonfinal": false,
            "enable_endpoint_detection": true
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: config),
              let jsonString = String(data: data, encoding: .utf8) else {
            apiTestState = .failure("配置序列化失败")
            return
        }

        task.send(.string(jsonString)) { error in
            if let error {
                DispatchQueue.main.async {
                    apiTestState = .failure("连接失败: \(error.localizedDescription)")
                }
                return
            }

            // Try to receive a response — if auth fails, server closes with error
            task.receive { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        apiTestState = .success
                    case .failure(let error):
                        let msg = error.localizedDescription
                        if msg.contains("57") || msg.contains("Socket is not connected") {
                            apiTestState = .failure("API Key 无效或连接被拒绝")
                        } else {
                            apiTestState = .failure(msg)
                        }
                    }
                    task.cancel(with: .normalClosure, reason: nil)
                }
            }

            // Send empty data to trigger end-of-audio, so server responds
            task.send(.data(Data())) { _ in }
        }
    }

    /// Test Groq/Cerebras/Deepgram by calling their models endpoint.
    private func testWhisperKey(apiKey: String, endpoint: String) {
        guard let url = URL(string: endpoint) else {
            apiTestState = .failure("无效的 URL")
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { _, response, error in
            DispatchQueue.main.async {
                if let error {
                    apiTestState = .failure("网络错误: \(error.localizedDescription)")
                    return
                }
                guard let httpResponse = response as? HTTPURLResponse else {
                    apiTestState = .failure("无响应")
                    return
                }
                switch httpResponse.statusCode {
                case 200:
                    apiTestState = .success
                case 401:
                    apiTestState = .failure("API Key 无效 (401)")
                case 403:
                    apiTestState = .failure("权限不足 (403)")
                default:
                    apiTestState = .failure("HTTP \(httpResponse.statusCode)")
                }
            }
        }.resume()
    }
}

#Preview {
    ContentView()
}
