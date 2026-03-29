//
//  STTProviderFactory.swift
//  VoiceKey
//
//  Factory that instantiates the correct StreamingSTTProvider based on
//  the user's selected engine in SettingsStore.
//

import Foundation

enum STTProviderFactory {

    /// Create a provider for the currently selected engine.
    /// - Parameters:
    ///   - engine: The STT engine to use.
    ///   - apiKey: The user's API key for this engine.
    ///   - languages: Recognition languages in priority order.
    ///   - model: Optional model override (from provider's model list).
    /// - Returns: A configured StreamingSTTProvider ready to `connect()`.
    static func makeProvider(
        engine: STTEngine,
        apiKey: String,
        languages: [RecognitionLanguage],
        model: String? = nil
    ) -> (any StreamingSTTProvider)? {
        guard !apiKey.isEmpty else { return nil }

        switch engine {
        case .soniox:
            let hints = LanguageManager.sonioxHints(for: languages)
            return SonioxStreamingService(
                apiKey: apiKey,
                languageHints: hints,
                model: model ?? "soniox_multilingual"
            )

        case .groq:
            let lang = LanguageManager.whisperLanguageCode(for: languages)
            let prompt = LanguageManager.whisperPromptHint(for: languages)
            return GroqSTTService(
                apiKey: apiKey,
                language: lang,
                prompt: prompt,
                model: model ?? "whisper-large-v3"
            )

        case .cerebras:
            let lang = LanguageManager.whisperLanguageCode(for: languages)
            let prompt = LanguageManager.whisperPromptHint(for: languages)
            return CerebrasSTTService(
                apiKey: apiKey,
                language: lang,
                prompt: prompt,
                model: model ?? "whisper-large-v3"
            )

        case .deepgram:
            // Placeholder — not yet implemented
            return nil
        }
    }
}
