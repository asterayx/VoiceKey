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
    @State private var fetchedModels: [String] = []
    @State private var isFetchingModels = false

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
                    .onChange(of: settings.sttEngine) { _, _ in
                        apiTestState = .idle
                        fetchedModels = []
                        settings.sttModel = ""
                    }

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

                // MARK: - Model Selection (shown after successful API test)
                if !fetchedModels.isEmpty {
                    Section {
                        Picker("Model", selection: $settings.sttModel) {
                            ForEach(fetchedModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                        .pickerStyle(.menu)
                    } header: {
                        Text("Model")
                    } footer: {
                        Text("从 \(settings.sttEngine.displayName) 远程获取的可用模型")
                    }
                }

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
                    statusRow("Model", value: settings.sttModel.isEmpty ? "未选择" : settings.sttModel)
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
                    if settings.sttEngine == engine {
                        apiTestState = .idle
                        fetchedModels = []
                    }
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
                            Text(isFetchingModels ? "获取模型列表..." : "验证中...")
                        case .success:
                            Label("验证通过", systemImage: "checkmark.circle.fill")
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

// MARK: - API Key Test & Model Fetch

enum APITestState: Equatable {
    case idle
    case testing
    case success
    case failure(String)
}

extension ContentView {

    func testAPIKey(engine: STTEngine, apiKey: String) {
        apiTestState = .testing
        isFetchingModels = false
        fetchedModels = []

        switch engine {
        case .soniox:
            testSonioxKey(apiKey: apiKey)
        case .groq:
            testAndFetchModels(apiKey: apiKey, endpoint: "https://api.groq.com/openai/v1/models", engine: engine)
        case .cerebras:
            testAndFetchModels(apiKey: apiKey, endpoint: "https://api.cerebras.ai/v1/models", engine: engine)
        case .deepgram:
            testAndFetchModels(apiKey: apiKey, endpoint: "https://api.deepgram.com/v1/projects", engine: engine)
        }
    }

    /// Test Soniox by opening a WebSocket and sending config.
    /// If config send succeeds and connection stays open for 2s, the key is valid.
    /// Soniox doesn't have a REST models endpoint, so use hardcoded list on success.
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

        var resolved = false

        // Listen for server error/close (invalid key triggers immediate close)
        task.receive { result in
            guard !resolved else { return }
            DispatchQueue.main.async {
                switch result {
                case .success(let message):
                    // Check if server sent an error JSON
                    if case .string(let text) = message,
                       let msgData = text.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: msgData) as? [String: Any],
                       let errorMsg = json["error"] as? String {
                        resolved = true
                        apiTestState = .failure(errorMsg)
                    } else {
                        // Valid response — key works
                        resolved = true
                        onSonioxTestSuccess()
                    }
                    task.cancel(with: .normalClosure, reason: nil)
                case .failure(let error):
                    resolved = true
                    apiTestState = .failure("API Key 无效: \(error.localizedDescription)")
                }
            }
        }

        // Send config
        task.send(.string(jsonString)) { error in
            if let error {
                guard !resolved else { return }
                resolved = true
                DispatchQueue.main.async {
                    apiTestState = .failure("连接失败: \(error.localizedDescription)")
                }
                return
            }

            // Config sent OK — wait 2s; if no error received, key is valid
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                guard !resolved else { return }
                resolved = true
                onSonioxTestSuccess()
                task.cancel(with: .normalClosure, reason: nil)
            }
        }
    }

    private func onSonioxTestSuccess() {
        apiTestState = .success
        fetchedModels = STTEngine.soniox.fallbackModels
        if settings.sttModel.isEmpty {
            settings.sttModel = fetchedModels.first ?? ""
        }
    }

    /// Test key via /models endpoint, then parse available models.
    private func testAndFetchModels(apiKey: String, endpoint: String, engine: STTEngine) {
        guard let url = URL(string: endpoint) else {
            apiTestState = .failure("无效的 URL")
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { data, response, error in
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
                    isFetchingModels = true
                    let models = parseModels(from: data, engine: engine)
                    if models.isEmpty {
                        // API valid but no models parsed — use fallback
                        fetchedModels = engine.fallbackModels
                    } else {
                        fetchedModels = models
                    }
                    // Auto-select first model if none selected
                    if settings.sttModel.isEmpty || !fetchedModels.contains(settings.sttModel) {
                        settings.sttModel = fetchedModels.first ?? ""
                    }
                    isFetchingModels = false
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

    /// Parse model IDs from OpenAI-compatible /v1/models response.
    /// Filters for STT-relevant models (whisper, speech, audio, transcri).
    private func parseModels(from data: Data?, engine: STTEngine) -> [String] {
        guard let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArray = json["data"] as? [[String: Any]] else {
            return []
        }

        let sttKeywords = ["whisper", "speech", "audio", "transcri", "stt", "asr"]

        let allModelIDs = dataArray.compactMap { $0["id"] as? String }

        let sttModels = allModelIDs.filter { id in
            let lower = id.lowercased()
            return sttKeywords.contains { lower.contains($0) }
        }.sorted()

        return sttModels
    }
}

#Preview {
    ContentView()
}
