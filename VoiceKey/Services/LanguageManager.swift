//
//  LanguageManager.swift
//  VoiceKey
//
//  Maps RecognitionLanguage to provider-specific language codes and hints.
//  RecognitionLanguage enum is defined in SettingsStore.swift (shared file).
//

import Foundation

// MARK: - Provider-specific mappings

enum LanguageManager {

    // MARK: - Soniox

    /// Convert recognition languages to Soniox language_hints array.
    static func sonioxHints(for languages: [RecognitionLanguage]) -> [String] {
        languages.compactMap { sonioxCode(for: $0) }
    }

    private static func sonioxCode(for lang: RecognitionLanguage) -> String? {
        switch lang {
        case .zhCN:  return "zh"
        case .zhYue: return "yue"
        case .en:    return "en"
        case .es:    return "es"
        case .pt:    return "pt"
        case .fr:    return "fr"
        case .de:    return "de"
        case .ja:    return "ja"
        }
    }

    // MARK: - Whisper (Groq / Cerebras)

    /// Primary language code for Whisper API (uses the first/highest-priority language).
    static func whisperLanguageCode(for languages: [RecognitionLanguage]) -> String {
        guard let first = languages.first else { return "en" }
        return whisperCode(for: first)
    }

    /// Prompt hint for mixed-language recognition (Whisper convention).
    /// Includes secondary language terms to improve mixed recognition.
    static func whisperPromptHint(for languages: [RecognitionLanguage]) -> String {
        // If Chinese and English are both selected, add a hint
        let hasZh = languages.contains(.zhCN) || languages.contains(.zhYue)
        let hasEn = languages.contains(.en)
        if hasZh && hasEn {
            return "以下是一段中英文混合的语音转录。"
        }
        return ""
    }

    private static func whisperCode(for lang: RecognitionLanguage) -> String {
        switch lang {
        case .zhCN:  return "zh"
        case .zhYue: return "zh"   // Whisper doesn't distinguish Cantonese well
        case .en:    return "en"
        case .es:    return "es"
        case .pt:    return "pt"
        case .fr:    return "fr"
        case .de:    return "de"
        case .ja:    return "ja"
        }
    }

    // MARK: - Provider language support matrix

    /// Returns whether a provider supports a given language.
    static func isSupported(_ lang: RecognitionLanguage, by engine: STTEngine) -> Bool {
        switch engine {
        case .soniox:
            return true  // Soniox multilingual supports all, including Cantonese
        case .groq, .cerebras:
            // Whisper supports all except Cantonese is unreliable
            return lang != .zhYue
        case .deepgram:
            return false  // Not yet implemented
        }
    }
}
