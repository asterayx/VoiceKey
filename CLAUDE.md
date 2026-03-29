# VoiceKey — Project Context for Claude Code

## What is VoiceKey

iOS 语音输入键盘：键盘扩展 + 主 App，将语音实时转换为文字输入。

## Key Documentation

- **`DEVELOPMENT_PLAN.md`** — 完整开发计划 (M1–M10)、架构设计、里程碑定义。修改架构或功能前必须先阅读此文件。
- **`SETUP_GUIDE.md`** — 从零搭建指南，包含 Xcode 配置、target 设置、文件结构。排查构建问题时参考此文件。

## Architecture: Background Audio Residency

核心架构参考 Typeless / Wispr Flow 模式：

- **主 App (VoiceKey)** = "录音机"：持有 AVAudioEngine，通过 `UIBackgroundModes: audio` 后台常驻，运行所有音频采集 + STT + LLM 服务
- **键盘扩展 (VoiceKeyboard)** = "遥控器"：纯 UI 控制器，不包含任何音频/ASR 代码
- **iOS 限制**：键盘扩展无法访问麦克风，所有录音必须在主 App 进程

### IPC Communication

- **键盘 → 主 App**: Darwin Notification (`com.asterayx.voicekey.command`) + App Group UserDefaults 传参
- **主 App → 键盘**: Darwin Notification (`com.asterayx.voicekey.sttUpdate`) + App Group 写结果
- **首次激活**: URL Scheme `voicekey://activate` 拉起主 App
- **Heartbeat**: 主 App 每 5s 写 `vk_app_alive` 时间戳，键盘检测存活状态决定用 Darwin Notification (alive) 还是 URL Scheme (dead)
- **协议定义**: `Shared/VoiceKeyContract.swift`（双 target 成员）

## Project Structure

```
VoiceKey/
├── VoiceKey/                    # 主 App target
│   ├── VoiceKeyApp.swift        # App 入口 + BackgroundAudioManager
│   ├── ContentView.swift
│   ├── SettingsStore.swift       # 共享设置 (App Group UserDefaults, 双 target)
│   ├── Views/
│   │   └── VoiceInputView.swift
│   └── Services/                # 所有音频/STT 服务 (仅主 App target)
│       ├── AudioCaptureService.swift
│       ├── AudioBufferWriter.swift
│       ├── SilenceDetector.swift
│       ├── StreamingSTTProvider.swift   # Protocol
│       ├── STTProviderFactory.swift
│       ├── SonioxStreamingService.swift # WebSocket streaming
│       ├── GroqSTTService.swift         # REST Whisper API
│       ├── CerebrasSTTService.swift     # REST Whisper API
│       └── LanguageManager.swift
├── VoiceKeyboard/               # 键盘扩展 target
│   ├── KeyboardViewController.swift  # UIInputViewController, 无音频代码
│   ├── Views/
│   │   ├── KeyboardView.swift        # QWERTY/数字/符号键盘
│   │   ├── DraftCanvasView.swift     # 可编辑预览区 (替代直接 textDocumentProxy)
│   │   └── CandidateBarView.swift    # 拼音候选栏
│   └── Input/
│       └── PinyinEngine.swift
├── Shared/
│   └── VoiceKeyContract.swift   # 双向 IPC 协议 (双 target 成员)
├── DEVELOPMENT_PLAN.md
├── SETUP_GUIDE.md
└── CLAUDE.md                    # 本文件
```

## Target Membership Rules

| 文件 | VoiceKey | VoiceKeyboard |
|------|----------|---------------|
| `VoiceKey/Services/*` | YES | NO |
| `VoiceKey/VoiceKeyApp.swift` | YES | NO |
| `VoiceKeyboard/*` | NO | YES |
| `Shared/VoiceKeyContract.swift` | YES | YES |
| `VoiceKey/SettingsStore.swift` | YES | YES |

## Key Technical Details

- **Development Team**: `EL6G8M5A96`
- **Bundle IDs**: 主 App `com.asterayx.VoiceKey`, 扩展 `com.asterayx.VoiceKey.VoiceKeyboard`
- **App Group**: `group.com.asterayx.voicekey`
- **8 种识别语言**: zhCN, zhYue(experimental), en, es, pt, fr, de, ja
- **5 种输出风格**: raw, chat, email, memo, literary
- **STT 引擎**: Soniox (WebSocket streaming), Groq (REST Whisper), Cerebras (REST Whisper)
- **API Key 存储**: 当前 UserDefaults，计划迁移到 Keychain

## Current Progress

- M1 (Settings + SharedStore): Done
- M2 (Keyboard UI + Soniox STT): Done
- Architecture restructure (Background Audio Residency): Done (code written, needs real-device testing)
- M3–M10: Not started (see DEVELOPMENT_PLAN.md)

## Development Rules

- **只 commit + push，不主动 create PR**
- **开发分支**: `claude/review-dev-plan-status-sd94t`
- 修改架构决策时同步更新 DEVELOPMENT_PLAN.md
- 修改构建配置时同步更新 SETUP_GUIDE.md
- Services 目录在 `VoiceKey/Services/`（主 App target），不在 VoiceKeyboard 下
