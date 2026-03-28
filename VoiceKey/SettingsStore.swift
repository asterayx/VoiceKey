//
//  SettingsStore.swift
//  VoiceKey
//
//  Created by Peng Chen on 28/3/26.
//

import Foundation
import Combine

/// Default keyboard input language
enum KeyboardLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case chinese = "zh"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: return "English"
        case .chinese: return "中文"
        }
    }
}

/// STT engine options
enum STTEngine: String, CaseIterable, Identifiable {
    case soniox = "soniox"
    case deepgram = "deepgram"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .soniox: return "Soniox"
        case .deepgram: return "Deepgram"
        }
    }
}

/// Shared settings via App Group, accessible from both the host app and keyboard extension.
final class SettingsStore: ObservableObject {

    static let shared = SettingsStore()

    private static let appGroupID = "group.com.asterayx.voicekey"

    private let defaults: UserDefaults

    // MARK: - Keys

    private enum Key {
        static let sttEngine      = "stt_engine"
        static let sonioxAPIKey   = "soniox_api_key"
        static let deepgramAPIKey = "deepgram_api_key"
        static let defaultLang    = "default_language"
    }

    // MARK: - Published Properties

    @Published var sttEngine: STTEngine {
        didSet { defaults.set(sttEngine.rawValue, forKey: Key.sttEngine) }
    }

    @Published var sonioxAPIKey: String {
        didSet { defaults.set(sonioxAPIKey, forKey: Key.sonioxAPIKey) }
    }

    @Published var deepgramAPIKey: String {
        didSet { defaults.set(deepgramAPIKey, forKey: Key.deepgramAPIKey) }
    }

    @Published var defaultLanguage: KeyboardLanguage {
        didSet { defaults.set(defaultLanguage.rawValue, forKey: Key.defaultLang) }
    }

    // MARK: - Computed

    /// Returns the API key for the currently selected engine.
    var activeAPIKey: String {
        switch sttEngine {
        case .soniox: return sonioxAPIKey
        case .deepgram: return deepgramAPIKey
        }
    }

    // MARK: - Init

    private init() {
        let suite = UserDefaults(suiteName: SettingsStore.appGroupID) ?? .standard
        self.defaults = suite

        let engineRaw = suite.string(forKey: Key.sttEngine) ?? STTEngine.soniox.rawValue
        self.sttEngine = STTEngine(rawValue: engineRaw) ?? .soniox
        self.sonioxAPIKey   = suite.string(forKey: Key.sonioxAPIKey)   ?? ""
        self.deepgramAPIKey = suite.string(forKey: Key.deepgramAPIKey) ?? ""
        let langRaw = suite.string(forKey: Key.defaultLang) ?? KeyboardLanguage.english.rawValue
        self.defaultLanguage = KeyboardLanguage(rawValue: langRaw) ?? .english
    }
}
