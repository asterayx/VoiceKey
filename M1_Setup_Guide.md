# M1 Setup Guide — VoiceKey

## Prerequisites

- Xcode 26.2+
- Apple Developer account (for device testing)
- Development Team: `EL6G8M5A96`

---

## 1. Create App Group

1. Open the project in Xcode, select **VoiceKey** target
2. Go to **Signing & Capabilities** → click **+ Capability** → **App Groups**
3. Add group: `group.com.asterayx.voicekey`

## 2. Add Keyboard Extension Target

1. **File → New → Target…**
2. Choose **Custom Keyboard Extension**
3. Settings:
   - Product Name: `VoiceKeyboard`
   - Bundle Identifier: `com.asterayx.VoiceKey.VoiceKeyboard`
   - Language: Swift
   - When prompted to activate scheme, click **Activate**
4. **Delete** the auto-generated `KeyboardViewController.swift` from the new target (we have our own)
5. Copy our files into the target:
   - Drag `VoiceKeyboard/KeyboardViewController.swift` into the **VoiceKeyboard** group in Xcode
   - Drag `VoiceKeyboard/Info.plist` into the **VoiceKeyboard** group
   - Set the Info.plist path in Build Settings: **VoiceKeyboard → Build Settings → Info.plist File** → `VoiceKeyboard/Info.plist`

## 3. Add App Group to Extension

1. Select **VoiceKeyboard** target
2. **Signing & Capabilities** → **+ Capability** → **App Groups**
3. Add the same group: `group.com.asterayx.voicekey`

## 4. Share SettingsStore with Both Targets

`SettingsStore.swift` must belong to **both** the VoiceKey app and VoiceKeyboard extension:

1. Select `SettingsStore.swift` in the Xcode navigator
2. Open the **File Inspector** (right panel)
3. Under **Target Membership**, check both:
   - [x] VoiceKey
   - [x] VoiceKeyboard

## 5. Microphone Permission (Extension)

Add to the **VoiceKeyboard** target's Info.plist (or build settings):

| Key | Value |
|-----|-------|
| `NSMicrophoneUsageDescription` | VoiceKey needs microphone access for speech-to-text input. |

> Note: The keyboard extension Info.plist already has `RequestsOpenAccess = YES`, which is required for microphone access.

## 6. Build & Run

1. Select scheme **VoiceKey** → build to simulator or device
2. On device/simulator:
   - Go to **Settings → General → Keyboard → Keyboards → Add New Keyboard**
   - Select **VoiceKey**
   - Tap **VoiceKey** again → enable **Allow Full Access** (required for network + mic)
3. Open any text field, switch to VoiceKey keyboard
4. Tap the mic button — you should see the placeholder text inserted

## File Summary

```
VoiceKey/
├── VoiceKeyApp.swift          # App entry point (unchanged)
├── ContentView.swift          # Settings UI — engine picker + API keys
├── SettingsStore.swift        # App Group shared settings (both targets)
└── Assets.xcassets/

VoiceKeyboard/
├── KeyboardViewController.swift  # Keyboard extension UI + mic button
└── Info.plist                    # Extension config (RequestsOpenAccess, etc.)
```

## What M1 Delivers

- Host app with engine selection (Soniox / Deepgram) and API key entry
- Settings shared via App Group between host app and keyboard extension
- Keyboard extension with mic button UI (placeholder action)
- Globe (next keyboard) button for switching keyboards

## Next: M2

- Wire mic button to AVAudioEngine for real-time audio capture
- Connect to Soniox / Deepgram WebSocket STT APIs
- Stream transcribed text into the text field
