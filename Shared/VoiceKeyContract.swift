//
//  VoiceKeyContract.swift
//  VoiceKey
//
//  Shared communication protocol between the main app and keyboard extension.
//  Both targets must include this file.
//
//  Communication flow:
//    Keyboard → Main App:  URL Scheme (voicekey://record, voicekey://command)
//    Main App → Keyboard:  App Group UserDefaults (status, result, partial)
//

import Foundation

// MARK: - App Group Constants

enum VoiceKeyContract {

    static let appGroupID = "group.com.asterayx.voicekey"

    /// URL Scheme for launching the main app from the keyboard extension.
    static let urlSchemeRecord  = "voicekey://record"
    static let urlSchemeCommand = "voicekey://command"

    // MARK: - UserDefaults Keys

    enum Key {
        /// Current STT session status (String raw value of VKStatus).
        static let sttStatus    = "vk_stt_status"
        /// Final recognized text from STT.
        static let sttResult    = "vk_stt_result"
        /// Partial (streaming) text update from STT.
        static let sttPartial   = "vk_stt_partial"
        /// Timestamp (TimeInterval) of the last result write — used for dedup.
        static let sttTimestamp = "vk_stt_timestamp"
        /// Error message if status == .error.
        static let sttError     = "vk_stt_error"
    }

    // MARK: - Shared UserDefaults accessor

    static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }
}

// MARK: - Session Status

enum VKStatus: String {
    case idle
    case recording
    case processing
    case done
    case error
}

// MARK: - Write helpers (used by main app)

extension VoiceKeyContract {

    static func setStatus(_ status: VKStatus) {
        sharedDefaults?.set(status.rawValue, forKey: Key.sttStatus)
    }

    static func setPartialText(_ text: String) {
        sharedDefaults?.set(text, forKey: Key.sttPartial)
    }

    static func setResult(_ text: String) {
        sharedDefaults?.set(text, forKey: Key.sttResult)
        sharedDefaults?.set(Date().timeIntervalSince1970, forKey: Key.sttTimestamp)
        sharedDefaults?.set(VKStatus.done.rawValue, forKey: Key.sttStatus)
    }

    static func setError(_ message: String) {
        sharedDefaults?.set(message, forKey: Key.sttError)
        sharedDefaults?.set(VKStatus.error.rawValue, forKey: Key.sttStatus)
    }

    static func resetSession() {
        let defaults = sharedDefaults
        defaults?.removeObject(forKey: Key.sttStatus)
        defaults?.removeObject(forKey: Key.sttResult)
        defaults?.removeObject(forKey: Key.sttPartial)
        defaults?.removeObject(forKey: Key.sttTimestamp)
        defaults?.removeObject(forKey: Key.sttError)
    }
}

// MARK: - Read helpers (used by keyboard extension)

extension VoiceKeyContract {

    static func currentStatus() -> VKStatus {
        guard let raw = sharedDefaults?.string(forKey: Key.sttStatus) else { return .idle }
        return VKStatus(rawValue: raw) ?? .idle
    }

    static func currentPartialText() -> String {
        sharedDefaults?.string(forKey: Key.sttPartial) ?? ""
    }

    static func currentResult() -> String {
        sharedDefaults?.string(forKey: Key.sttResult) ?? ""
    }

    static func currentTimestamp() -> TimeInterval {
        sharedDefaults?.double(forKey: Key.sttTimestamp) ?? 0
    }

    static func currentError() -> String {
        sharedDefaults?.string(forKey: Key.sttError) ?? ""
    }
}
