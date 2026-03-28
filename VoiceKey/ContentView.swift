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
                    .pickerStyle(.segmented)
                }

                // MARK: - API Keys
                Section {
                    SecureField("Soniox API Key", text: $settings.sonioxAPIKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                } header: {
                    Text("Soniox")
                } footer: {
                    Text("Get your key at console.soniox.com")
                }

                Section {
                    SecureField("Deepgram API Key", text: $settings.deepgramAPIKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                } header: {
                    Text("Deepgram")
                } footer: {
                    Text("Get your key at console.deepgram.com")
                }

                // MARK: - Language
                Section("Keyboard Default Language") {
                    Picker("Default Language", selection: $settings.defaultLanguage) {
                        ForEach(KeyboardLanguage.allCases) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // MARK: - Status
                Section("Status") {
                    HStack {
                        Text("Active Engine")
                        Spacer()
                        Text(settings.sttEngine.displayName)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Default Language")
                        Spacer()
                        Text(settings.defaultLanguage.displayName)
                            .foregroundStyle(.secondary)
                    }
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
}

#Preview {
    ContentView()
}
