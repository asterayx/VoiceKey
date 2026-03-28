//
//  VoiceKeyContract.swift
//  VoiceKey
//
//  Shared communication protocol between the main app and keyboard extension.
//  Both targets must include this file.
//
//  Communication flow (bidirectional Darwin Notification IPC):
//    Keyboard → Main App:  Darwin Notification (command) + App Group UserDefaults
//    Main App → Keyboard:  Darwin Notification (update)  + App Group UserDefaults
//    Keyboard → Main App:  URL Scheme (first activation / reactivation only)
//

import Foundation

// MARK: - App Group Constants

enum VoiceKeyContract {

    static let appGroupID = "group.com.asterayx.voicekey"

    /// URL Scheme for first-time activation (launches main app to start background audio).
    /// Only used when main app is not running in background.
    static let urlSchemeActivate = "voicekey://activate"

    // MARK: - Darwin Notification Names

    /// Main app → keyboard: STT status/result updated, read from UserDefaults.
    static let notifySTTUpdate = "com.asterayx.voicekey.sttUpdate" as CFString
    /// Keyboard → main app: command issued, read vk_command from UserDefaults.
    static let notifyCommand   = "com.asterayx.voicekey.command" as CFString

    // MARK: - UserDefaults Keys

    enum Key {
        // --- Main App → Keyboard (STT results) ---
        /// Current STT session status (String raw value of VKStatus).
        static let sttStatus    = "vk_stt_status"
        /// Final recognized text from STT.
        static let sttResult    = "vk_stt_result"
        /// Partial (streaming) text update from STT.
        static let sttPartial   = "vk_stt_partial"
        /// Timestamp (TimeInterval) of the last result write — used for dedup.
        static let sttTimestamp  = "vk_stt_timestamp"
        /// Error message if status == .error.
        static let sttError     = "vk_stt_error"

        // --- Keyboard → Main App (commands) ---
        /// Command type (String raw value of VKCommand).
        static let command          = "vk_command"
        /// Command timestamp (TimeInterval) — used for dedup.
        static let commandTimestamp = "vk_command_timestamp"

        // --- Heartbeat (Main App liveness) ---
        /// TimeInterval written by main app every ~5s while background audio is active.
        /// Keyboard checks this to decide URL Scheme vs Darwin Notification.
        static let appAlive = "vk_app_alive"
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

// MARK: - Commands (Keyboard → Main App)

enum VKCommand: String {
    case startRecording
    case stopRecording
    case cancel
}

// MARK: - Write helpers (used by main app → keyboard)

extension VoiceKeyContract {

    static func setStatus(_ status: VKStatus) {
        sharedDefaults?.set(status.rawValue, forKey: Key.sttStatus)
        postNotification(notifySTTUpdate)
    }

    static func setPartialText(_ text: String) {
        sharedDefaults?.set(text, forKey: Key.sttPartial)
        postNotification(notifySTTUpdate)
    }

    static func setResult(_ text: String) {
        sharedDefaults?.set(text, forKey: Key.sttResult)
        sharedDefaults?.set(Date().timeIntervalSince1970, forKey: Key.sttTimestamp)
        sharedDefaults?.set(VKStatus.done.rawValue, forKey: Key.sttStatus)
        postNotification(notifySTTUpdate)
    }

    static func setError(_ message: String) {
        sharedDefaults?.set(message, forKey: Key.sttError)
        sharedDefaults?.set(VKStatus.error.rawValue, forKey: Key.sttStatus)
        postNotification(notifySTTUpdate)
    }

    static func resetSession() {
        let defaults = sharedDefaults
        defaults?.removeObject(forKey: Key.sttStatus)
        defaults?.removeObject(forKey: Key.sttResult)
        defaults?.removeObject(forKey: Key.sttPartial)
        defaults?.removeObject(forKey: Key.sttTimestamp)
        defaults?.removeObject(forKey: Key.sttError)
    }

    /// Write heartbeat timestamp (call from main app on a 5s timer).
    static func updateHeartbeat() {
        sharedDefaults?.set(Date().timeIntervalSince1970, forKey: Key.appAlive)
    }
}

// MARK: - Write helpers (used by keyboard → main app)

extension VoiceKeyContract {

    /// Send a command to the main app via App Group + Darwin Notification.
    static func sendCommand(_ command: VKCommand) {
        sharedDefaults?.set(command.rawValue, forKey: Key.command)
        sharedDefaults?.set(Date().timeIntervalSince1970, forKey: Key.commandTimestamp)
        postNotification(notifyCommand)
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

    /// Check if the main app is alive in background (heartbeat within last 10s).
    static func isAppAlive() -> Bool {
        let lastHeartbeat = sharedDefaults?.double(forKey: Key.appAlive) ?? 0
        guard lastHeartbeat > 0 else { return false }
        return Date().timeIntervalSince1970 - lastHeartbeat < 10.0
    }
}

// MARK: - Read helpers (used by main app to receive commands)

extension VoiceKeyContract {

    static func currentCommand() -> VKCommand? {
        guard let raw = sharedDefaults?.string(forKey: Key.command) else { return nil }
        return VKCommand(rawValue: raw)
    }

    static func currentCommandTimestamp() -> TimeInterval {
        sharedDefaults?.double(forKey: Key.commandTimestamp) ?? 0
    }

    static func clearCommand() {
        sharedDefaults?.removeObject(forKey: Key.command)
        sharedDefaults?.removeObject(forKey: Key.commandTimestamp)
    }
}

// MARK: - Darwin Notification Helpers

extension VoiceKeyContract {

    /// Post a Darwin notification.
    static func postNotification(_ name: CFString) {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(center, CFNotificationName(name), nil, nil, true)
    }

    /// Register to observe a Darwin notification.
    /// - Parameters:
    ///   - name: The notification name to observe.
    ///   - callback: Invoked on the main thread when notification is received.
    static func observeNotification(_ name: CFString, callback: @escaping () -> Void) {
        let center = CFNotificationCenterGetDarwinNotifyCenter()

        // Store callback in the appropriate slot
        if name == notifySTTUpdate {
            _sttUpdateCallback = callback
        } else if name == notifyCommand {
            _commandCallback = callback
        }

        let cfCallback: CFNotificationCallback = { _, _, notifName, _, _ in
            DispatchQueue.main.async {
                guard let n = notifName?.rawValue as CFString? else { return }
                if n == VoiceKeyContract.notifySTTUpdate {
                    VoiceKeyContract._sttUpdateCallback?()
                } else if n == VoiceKeyContract.notifyCommand {
                    VoiceKeyContract._commandCallback?()
                }
            }
        }

        CFNotificationCenterAddObserver(center, nil, cfCallback, name, nil, .deliverImmediately)
    }

    /// Remove observer for a specific Darwin notification.
    static func removeObserver(for name: CFString) {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterRemoveObserver(center, nil, CFNotificationName(name), nil)
        if name == notifySTTUpdate { _sttUpdateCallback = nil }
        if name == notifyCommand   { _commandCallback = nil }
    }

    /// Remove all Darwin notification observers.
    static func removeAllObservers() {
        removeObserver(for: notifySTTUpdate)
        removeObserver(for: notifyCommand)
    }

    // Stored callbacks (global, one per notification type)
    private static var _sttUpdateCallback: (() -> Void)?
    private static var _commandCallback: (() -> Void)?
}
