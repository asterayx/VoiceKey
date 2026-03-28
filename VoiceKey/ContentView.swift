//
//  ContentView.swift
//  VoiceKey
//
//  Created by Peng Chen on 28/3/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var settings = SettingsStore.shared

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

#Preview {
    ContentView()
}
