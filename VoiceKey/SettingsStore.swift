//
//  SettingsStore.swift
//  VoiceKey
//
//  Created by Peng Chen on 28/3/26.
//
//  Shared settings via App Group, accessible from both the host app
//  and keyboard extension.
//

import Foundation
import Combine

// MARK: - STT Engine

enum STTEngine: String, CaseIterable, Identifiable {
    case soniox   = "soniox"
    case groq     = "groq"
    case cerebras = "cerebras"
    case deepgram = "deepgram"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .soniox:   return "Soniox"
        case .groq:     return "Groq"
        case .cerebras: return "Cerebras"
        case .deepgram: return "Deepgram"
        }
    }

    var supportsStreaming: Bool {
        switch self {
        case .soniox:   return true
        case .groq:     return false
        case .cerebras: return false
        case .deepgram: return false
        }
    }
}

// MARK: - Output Style (for future LLM post-processing)

enum OutputStyle: String, CaseIterable, Identifiable {
    case raw      = "raw"
    case chat     = "chat"
    case email    = "email"
    case memo     = "memo"
    case literary = "literary"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .raw:      return "原始文本"
        case .chat:     return "聊天风格"
        case .email:    return "正式邮件"
        case .memo:     return "备忘录"
        case .literary: return "文艺风格"
        }
    }
}

// MARK: - Settings Store

final class SettingsStore: ObservableObject {

    static let shared = SettingsStore()

    private static let appGroupID = "group.com.asterayx.voicekey"

    private let defaults: UserDefaults

    // MARK: - Keys

    private enum Key {
        static let sttEngine       = "stt_engine"
        static let sonioxAPIKey    = "soniox_api_key"
        static let groqAPIKey      = "groq_api_key"
        static let cerebrasAPIKey  = "cerebras_api_key"
        static let deepgramAPIKey  = "deepgram_api_key"
        static let activeLanguages = "active_languages"
        static let silenceTimeout  = "silence_timeout"
        static let wsIdleTimeout   = "ws_idle_timeout"
        static let outputStyle     = "output_style"
        static let sttModel        = "stt_model"
    }

    // MARK: - Published Properties

    @Published var sttEngine: STTEngine {
        didSet { defaults.set(sttEngine.rawValue, forKey: Key.sttEngine) }
    }

    @Published var sonioxAPIKey: String {
        didSet { defaults.set(sonioxAPIKey, forKey: Key.sonioxAPIKey) }
    }

    @Published var groqAPIKey: String {
        didSet { defaults.set(groqAPIKey, forKey: Key.groqAPIKey) }
    }

    @Published var cerebrasAPIKey: String {
        didSet { defaults.set(cerebrasAPIKey, forKey: Key.cerebrasAPIKey) }
    }

    @Published var deepgramAPIKey: String {
        didSet { defaults.set(deepgramAPIKey, forKey: Key.deepgramAPIKey) }
    }

    /// Languages in priority order. First language has highest priority.
    @Published var activeLanguages: [RecognitionLanguage] {
        didSet {
            let raw = activeLanguages.map(\.rawValue)
            defaults.set(raw, forKey: Key.activeLanguages)
        }
    }

    /// Seconds of silence before auto-stop (1–10).
    @Published var silenceTimeoutSeconds: Double {
        didSet { defaults.set(silenceTimeoutSeconds, forKey: Key.silenceTimeout) }
    }

    /// Seconds of no audio before disconnecting WebSocket (0 = never).
    @Published var webSocketIdleTimeoutSeconds: Double {
        didSet { defaults.set(webSocketIdleTimeoutSeconds, forKey: Key.wsIdleTimeout) }
    }

    /// Default output style for LLM post-processing.
    @Published var outputStyle: OutputStyle {
        didSet { defaults.set(outputStyle.rawValue, forKey: Key.outputStyle) }
    }

    /// Selected STT model name (provider-specific).
    @Published var sttModel: String {
        didSet { defaults.set(sttModel, forKey: Key.sttModel) }
    }

    // MARK: - Computed

    /// Returns the API key for the currently selected engine.
    var activeAPIKey: String {
        switch sttEngine {
        case .soniox:   return sonioxAPIKey
        case .groq:     return groqAPIKey
        case .cerebras: return cerebrasAPIKey
        case .deepgram: return deepgramAPIKey
        }
    }

    // MARK: - Init

    private init() {
        let suite = UserDefaults(suiteName: SettingsStore.appGroupID) ?? .standard
        self.defaults = suite

        // STT engine
        let engineRaw = suite.string(forKey: Key.sttEngine) ?? STTEngine.soniox.rawValue
        self.sttEngine = STTEngine(rawValue: engineRaw) ?? .soniox

        // API keys
        self.sonioxAPIKey   = suite.string(forKey: Key.sonioxAPIKey)   ?? ""
        self.groqAPIKey     = suite.string(forKey: Key.groqAPIKey)     ?? ""
        self.cerebrasAPIKey = suite.string(forKey: Key.cerebrasAPIKey) ?? ""
        self.deepgramAPIKey = suite.string(forKey: Key.deepgramAPIKey) ?? ""

        // Active languages
        if let rawLangs = suite.stringArray(forKey: Key.activeLanguages) {
            self.activeLanguages = rawLangs.compactMap { RecognitionLanguage(rawValue: $0) }
        } else {
            self.activeLanguages = [.zhCN, .en]  // Default: Chinese + English
        }

        // Silence timeout
        let silence = suite.double(forKey: Key.silenceTimeout)
        self.silenceTimeoutSeconds = silence > 0 ? silence : 3.0

        // WebSocket idle timeout
        let wsIdle = suite.double(forKey: Key.wsIdleTimeout)
        self.webSocketIdleTimeoutSeconds = wsIdle > 0 ? wsIdle : 30.0

        // Output style
        let styleRaw = suite.string(forKey: Key.outputStyle) ?? OutputStyle.raw.rawValue
        self.outputStyle = OutputStyle(rawValue: styleRaw) ?? .raw

        // STT model
        self.sttModel = suite.string(forKey: Key.sttModel) ?? ""
    }
}
