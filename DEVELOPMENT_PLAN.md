# VoiceKey 开发计划 (M3–M10) — 修订版

## Context

VoiceKey 是一个 iOS 键盘扩展 + 主 App，将语音实时转换为文字输入。M1（设置+共享存储）和 M2（键盘UI+Soniox STT）已完成。

### 架构修订原因

原计划将录音和 ASR 放在键盘扩展中，但 **iOS 键盘扩展无法访问麦克风**（即使开启 Full Access）。因此需要将所有音频/ASR/LLM 服务迁移到主 App，键盘扩展仅作为触发器和文本编辑器。

## 新架构

```
┌─────────────────────────────┐     URL Scheme      ┌──────────────────────────────┐
│     VoiceKeyboard (扩展)     │ ──────────────────→ │       VoiceKey (主 App)        │
│                             │                      │                              │
│  • QWERTY/拼音/数字键盘      │     App Group        │  • AudioCaptureService        │
│  • DraftCanvas (文本预览编辑) │ ←──────────────────→ │  • STT Providers (Soniox等)    │
│  • 语言切换                  │   UserDefaults       │  • LLM Providers              │
│  • 触发录音 (URL Scheme)     │   shared container   │  • VoiceInputView (录音UI)     │
│  • 读取识别结果               │                      │  • Settings UI                │
│  • 插入到宿主 App            │                      │                              │
└─────────────────────────────┘                      └──────────────────────────────┘
```

### 通信协议

**键盘 → 主 App**: URL Scheme
- `voicekey://record` — 启动录音
- `voicekey://command?text=...` — 编辑命令模式

**主 App → 键盘**: App Group UserDefaults + Darwin 通知
- `vk_stt_result` — ASR 识别结果文本
- `vk_stt_status` — 状态 (idle/recording/processing/done/error)
- `vk_stt_partial` — 流式 partial 文本（Soniox）
- `vk_stt_timestamp` — 结果时间戳（用于去重）
- `vk_stt_error` — 具体错误信息（网络断开、API Key 无效、录音权限拒绝等）

**实时通知（替代轮询）**: 主 App 写入 UserDefaults 后通过 `CFNotificationCenterGetDarwinNotifyCenter` 发送 `com.asterayx.voicekey.sttUpdate` 通知，键盘扩展监听后立即读取，省电且实时性更高。Timer 轮询仅作兜底（防止通知丢失）。

### 交互流程

1. 用户在任意 App 中使用 VoiceKey 键盘
2. 点击 🎤 → 键盘通过 URL Scheme 拉起主 App
3. 主 App 自动开始录音 + ASR
4. ASR 结果实时写入 App Group UserDefaults
5. 用户完成录音后，主 App 写入最终结果
6. 用户切回宿主 App（键盘自动恢复）
7. 键盘从 App Group 读取结果，显示在 DraftCanvas
8. 用户在 DraftCanvas 中预览/编辑（键盘或语音命令）
9. 用户确认后，文本插入到宿主 App 的编辑框

## iOS 键盘扩展关键约束

- **无麦克风访问**: 即使 Full Access 也不行，必须通过主 App 录音
- **内存限制**: ~48-60MB，但迁移服务后键盘扩展内存压力大幅降低
- **后台运行**: 不可能。键盘收起或锁屏后扩展被挂起
- **textDocumentProxy**: selectedText 不可靠，用 DraftCanvas 替代
- **防熄屏**: 键盘扩展无法控制；主 App 可通过 `isIdleTimerDisabled = true`

## 安全策略

- **API Key 存储**: 所有 API Key 使用 **Keychain** 存储（而非 UserDefaults/App Group），主 App 与键盘扩展通过 **Keychain Sharing**（同一 Keychain Access Group）共享。Keychain 是 Apple 推荐的敏感信息存储方式，具备硬件级加密保护。
- **App Group UserDefaults**: 仅用于非敏感数据（STT 状态、识别结果文本、设置偏好）。

---

## M3: 架构重构 — 服务迁移 + 通信协议

**目标**: 将所有音频/ASR 服务从键盘扩展迁移到主 App，建立 URL Scheme + App Group 通信。

**新建文件**:
- `Shared/VoiceKeyContract.swift` — App Group 通信协议（双 target 共享）
  - UserDefaults key 常量
  - `VKStatus` 枚举 (idle/recording/processing/done/error)
  - 读写便利方法
- `VoiceKey/Views/VoiceInputView.swift` — 主 App 录音界面（录音按钮+实时文本+完成按钮）

**迁移文件** (VoiceKeyboard/Services/ → VoiceKey/Services/):
- `StreamingSTTProvider.swift`
- `STTProviderFactory.swift`
- `SonioxStreamingService.swift`
- `GroqSTTService.swift`
- `CerebrasSTTService.swift`
- `AudioCaptureService.swift`
- `AudioBufferWriter.swift`
- `SilenceDetector.swift`
- `LanguageManager.swift`

**修改文件**:
- `VoiceKeyApp.swift` — 注册 URL Scheme，处理 `voicekey://record` 和 `voicekey://command`
- `KeyboardViewController.swift` — 移除所有 audio/STT 代码，改为 URL Scheme 触发 + App Group 轮询
- `SettingsStore.swift` — 头部注释更新（无需改动）

**删除文件**:
- `VoiceKeyboard/Views/TranscriptionBannerView.swift` — 被 DraftCanvasView 替代

**架构决策**:
- 键盘扩展通过 `UIApplication.shared.open(url)` 拉起主 App（需 Full Access）
- 主 App 用 `onOpenURL` 处理 URL Scheme
- **事件驱动通信**: 主 App 写入 UserDefaults 后通过 `CFNotificationCenterGetDarwinNotifyCenter` 发送 Darwin 通知，键盘扩展监听后立即读取结果。Timer 轮询（0.5s 间隔）仅作兜底机制
- DraftCanvas 是一个 UITextView，用户可直接编辑文本
- **错误处理**: 主 App 出错时写入 `vk_stt_error`（含具体错误信息：网络断开、API Key 无效、服务不可用等），键盘端在 DraftCanvas 中显示具体错误提示而非空白等待
- **降级处理**: 键盘检测到主 App 未运行或无响应（URL Scheme 5s 内无状态变更）时显示"请手动打开 VoiceKey App"
- API Key 迁移到 Keychain 存储，通过 Keychain Sharing 跨 target 共享

**依赖**: 无（重构基础）

---

## M4: DraftCanvas + 键盘编辑体验

**目标**: 在键盘扩展中实现 DraftCanvas，替代直接 textDocumentProxy 操作。

**新建文件**:
- `VoiceKeyboard/Views/DraftCanvasView.swift` — 可编辑文本区域
  - UITextView 基础
  - 显示 ASR 结果（partial 灰色 + final 黑色）
  - 确认按钮（插入到宿主 App）
  - 清除按钮
  - 状态指示（等待中/已收到结果）

**修改文件**:
- `KeyboardViewController.swift` — 集成 DraftCanvas，管理展示/隐藏逻辑
- `KeyboardView.swift` — Mic 按钮状态更新（idle → waiting → hasResult）

**交互设计**:
1. 点击 🎤 → 打开 DraftCanvas + 跳转主 App
2. DraftCanvas 显示 "等待录音结果..."
3. 主 App 出错 → DraftCanvas 显示具体错误（如"Soniox 服务不可用，请检查网络"、"API Key 无效"、"录音权限被拒绝"）
4. 主 App 录音完成 → DraftCanvas 显示结果
5. 用户可在 DraftCanvas 中用键盘编辑文本
6. 点击 ✓ 确认 → 文本通过 textDocumentProxy.insertText() 插入
7. 点击 ✕ 取消 → 清空 DraftCanvas
8. 支持 Markdown 简单高亮预留（如命令模式返回的修改部分用蓝色标注），为 M7 做准备

**依赖**: M3

---

## M5: 多语言支持 + 键盘 UI 完善

**目标**: 完善 8 种语言支持，优化键盘 UI。

**修改文件**:
- `VoiceKey/Services/LanguageManager.swift` — 确保所有服务商的语言映射正确
- `KeyboardView.swift` — 语言切换按钮优化
- `ContentView.swift` — 语言选择 UI 优化（拖拽排序优先级）
- `VoiceInputView.swift` — 录音界面显示当前语言

**语言列表**: zhCN(普通话), zhYue(粤语), en, es, pt, fr, de, ja

> **注意**: 粤语(zhYue)目前 Soniox/Groq 等服务商支持较弱（多为实验性），优先级较低。后续根据实际识别率决定是否保留或降级为"Beta"标签。

**依赖**: M3, M4

---

## M6: LLM 后处理引擎

**目标**: 集成 LLM 对 ASR 输出进行后处理——去填充词、多种输出风格。

**新建文件** (VoiceKey/Services/):
- `LLMProvider.swift` — 协议
- `OpenAICompatibleLLMService.swift` — 通用实现（OpenAI/Groq/Cerebras/Grok）
- `AnthropicLLMService.swift` — Anthropic Messages API
- `GeminiLLMService.swift` — Google Gemini API
- `LLMProviderFactory.swift` — 工厂
- `PromptTemplates.swift` — 输出风格模板（raw/chat/email/memo/literary）

**修改文件**:
- `SettingsStore.swift` — LLM 服务商枚举、API Key、模型选择
- `ContentView.swift` — LLM 配置 UI
- `VoiceInputView.swift` — 录音完成后自动调用 LLM 后处理

**内置端点**:
| 服务商 | 端点 |
|--------|------|
| OpenAI | `api.openai.com/v1` |
| Anthropic | `api.anthropic.com/v1` |
| Google Gemini | `generativelanguage.googleapis.com/v1beta` |
| Groq | `api.groq.com/openai/v1` |
| Cerebras | `api.cerebras.ai/v1` |
| Grok (xAI) | `api.x.ai/v1` |

**依赖**: M3

---

## M7: 语音命令编辑模式

**目标**: 通过语音命令在 DraftCanvas 中编辑文本。

**新建文件** (VoiceKey/Services/):
- `CommandParser.swift` — 解析命令关键词（同音字、数字转换、翻译等）
- `EditCommandExecutor.swift` — 命令 + 文本 → LLM → 结果
- `HomophoneEngine.swift` — PinyinEngine 反向查找

**修改文件**:
- `KeyboardView.swift` — 启用编辑按钮
- `KeyboardViewController.swift` — 编辑模式状态机：
  1. 点击 ✏️ → 获取 DraftCanvas 中选中的文本（UITextView.selectedRange）
  2. 通过 URL Scheme 跳转主 App 录音（命令模式）
  3. 主 App 识别语音命令
  4. 命令 + 选中文本 → LLM 处理
  5. 结果写回 DraftCanvas 替换选中文本
- `VoiceInputView.swift` — 命令模式 UI

**DraftCanvas 选中文本同步注意事项**:
- UITextView 在键盘扩展里取 `selectedRange` 是可以的
- 在键盘收起/切换 App 时，`textDocumentProxy` 的状态可能与 DraftCanvas 不同步
- 确认插入前做一次 `textDocumentProxy.documentContextBeforeInput` 校验，确保插入位置与用户预期一致
- 命令模式返回的修改部分用蓝色高亮标注差异，方便用户确认

**依赖**: M4（DraftCanvas）, M6（LLM 引擎）

---

## M8: 自定义词典 + 输入历史

**目标**: 自定义词典提升准确度；记录输入历史。

**新建文件**:
- `VoiceKey/Models/CustomDictionary.swift` — 词典模型
- `VoiceKey/Models/InputRecord.swift` — 输入记录模型
- `VoiceKey/Views/DictionaryView.swift` — 词典管理 UI
- `VoiceKey/Views/HistoryView.swift` — 历史列表 + 统计

**修改文件**:
- `ContentView.swift` — 导航到词典和历史
- STT 服务文件 — 传入自定义词典
- `VoiceInputView.swift` — 录音完成后保存记录

**依赖**: M6

---

## M9: 独立语音输入界面增强

**目标**: 主 App 独立语音输入支持长录音、防熄屏、后台音频。

**修改文件**:
- `VoiceInputView.swift` — 大型录音按钮、实时波形、风格选择、一键复制/分享
- `VoiceKeyApp.swift` — 添加 `UIBackgroundModes: audio`
- `Info.plist` — Background Audio entitlement

**Info.plist 必需声明**（后台模式下可能被单独检查）:
- `NSMicrophoneUsageDescription` — 麦克风权限说明
- `NSSpeechRecognitionUsageDescription` — 语音识别权限说明（即使使用第三方 ASR 也建议声明）
- `UIBackgroundModes: audio` — 后台音频

**防熄屏**: 录音期间 `isIdleTimerDisabled = true`

**电量保护**: 长录音场景增加剩余电量检测，电量 < 20% 时自动停止录音并保存已有结果，弹窗提示用户"电量不足，已自动保存"。通过 `UIDevice.current.batteryLevel` + `UIDevice.current.isBatteryMonitoringEnabled` 实现。

**依赖**: M3, M6

---

## M10: 性能优化 + 可扩展性

**目标**: 优化网络/内存/电池，完善连接管理。

**优化项**:
- WebSocket 空闲断开策略调优
- HTTP 请求复用 URLSession
- LLM 流式响应（SSE）
- 音频缓冲上限审计
- didReceiveMemoryWarning 处理
- 新增服务商扩展预留（ElevenLabs 等）

**依赖**: M3–M9

---

## 里程碑依赖关系

```
M3 (架构重构) ──→ M4 (DraftCanvas) ──→ M5 (多语言+UI)
       │                │
       │                └──→ M7 (语音命令编辑)
       │
       └──→ M6 (LLM 后处理) ──→ M7
                   │
            ┌──────┼──────┐
            ▼      ▼      ▼
          M8     M9     M10
        (词典)  (独立UI) (性能)
```

## Target 文件结构（M3 完成后）

```
VoiceKey/                          ← 主 App target
├── VoiceKeyApp.swift              ← URL Scheme 处理
├── ContentView.swift              ← 设置 UI
├── SettingsStore.swift            ← 共享设置（双 target）
├── Views/
│   └── VoiceInputView.swift       ← 录音界面
└── Services/
    ├── StreamingSTTProvider.swift
    ├── STTProviderFactory.swift
    ├── SonioxStreamingService.swift
    ├── GroqSTTService.swift
    ├── CerebrasSTTService.swift
    ├── AudioCaptureService.swift
    ├── AudioBufferWriter.swift
    ├── SilenceDetector.swift
    └── LanguageManager.swift

Shared/                            ← 双 target 共享
└── VoiceKeyContract.swift         ← App Group 通信协议

VoiceKeyboard/                     ← 键盘扩展 target
├── KeyboardViewController.swift   ← 轻量化（无音频/ASR）
├── Info.plist
├── Input/
│   └── PinyinEngine.swift
└── Views/
    ├── KeyboardView.swift
    ├── DraftCanvasView.swift       ← 新：可编辑文本预览
    └── CandidateBarView.swift
```

## 验证方法

每个里程碑完成后：
1. **编译验证**: GitHub Actions CI 确保构建通过
2. **模拟器测试**: 在 iOS Simulator 上验证 UI 交互
3. **真机测试**: 在 iPhone 上安装，验证 URL Scheme 跳转、App Group 通信、录音功能
4. **内存审计**: 键盘扩展 < 30MB，主 App < 100MB
5. **单元测试覆盖**（M6+ 逐步补充）:
   - `StreamingSTTProvider` 协议一致性
   - `CommandParser` 命令解析（M7）
   - `EditCommandExecutor` 命令执行（M7）
   - `LLMProviderFactory` 工厂分支覆盖（M6）
   - `VoiceKeyContract` 读写一致性
6. **集成测试场景**:
   - 主 App 被杀掉后键盘能否优雅降级（显示"主 App 未运行，请手动打开 VoiceKey"）
   - URL Scheme 跳转后主 App 无响应的超时处理
   - App Group UserDefaults 写入/读取跨进程一致性
   - 长录音 + 后台音频 + 低电量自动保存
