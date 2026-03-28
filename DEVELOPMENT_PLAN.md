# VoiceKey 开发计划 (M3–M10) — 修订版

## Context

VoiceKey 是一个 iOS 键盘扩展 + 主 App，将语音实时转换为文字输入。M1（设置+共享存储）和 M2（键盘UI+Soniox STT）已完成。

### 架构修订原因

原计划将录音和 ASR 放在键盘扩展中，但 **iOS 键盘扩展无法访问麦克风**（即使开启 Full Access）。因此需要将所有音频/ASR/LLM 服务迁移到主 App，键盘扩展仅作为触发器和文本编辑器。

## 新架构

```
┌─────────────────────────────┐   Darwin Notify     ┌──────────────────────────────┐
│     VoiceKeyboard (扩展)     │ ──────────────────→ │       VoiceKey (主 App)        │
│     「遥控器」               │   vk_command        │       「录音机」(后台常驻)       │
│                             │                      │                              │
│  • QWERTY/拼音/数字键盘      │   Darwin Notify     │  • AudioCaptureService        │
│  • DraftCanvas (文本预览编辑) │ ←────────────────── │  • STT Providers (Soniox等)    │
│  • 语言切换                  │   vk_sttUpdate      │  • LLM Providers              │
│  • 触发录音 (IPC 遥控)       │                      │  • VoiceInputView (录音UI)     │
│  • 读取识别结果               │   App Group          │  • Background Audio Session   │
│  • 直接插入到宿主 App        │ ←──────────────────→ │  • Settings UI                │
│                             │   UserDefaults       │                              │
└─────────────────────────────┘                      └──────────────────────────────┘
```

### 核心理念：后台麦克风常驻 (Background Audio Residency)

参考 Typeless / Wispr Flow 的成熟方案：

1. **首次激活**: 用户第一次点击键盘 🎤 → URL Scheme 拉起主 App → 主 App 激活 `AVAudioEngine` + `UIBackgroundModes: audio` → 自动跳回宿主 App
2. **后台常驻**: 主 App 在后台持续占用麦克风（状态栏橙色圆点），等待键盘指令
3. **后续使用无需跳转**: 键盘点击 🎤 → 通过 Darwin Notification 向后台主 App 发送"开始录音"信号 → 主 App 在后台直接处理 → 结果写入 App Group → 键盘读取并插入
4. **整个过程用户停留在宿主 App 中，无需切换**

### 通信协议

**键盘 → 主 App**（双通道）:
- **首次激活**: URL Scheme `voicekey://activate` — 拉起主 App 并激活后台音频会话
- **后续录音**: Darwin Notification `com.asterayx.voicekey.command` — 无需跳转
- App Group UserDefaults 命令参数:
  - `vk_command` — 命令类型 (startRecording/stopRecording/cancel)
  - `vk_command_timestamp` — 命令时间戳（去重）

**主 App → 键盘**（Darwin 通知 + App Group）:
- Darwin Notification `com.asterayx.voicekey.sttUpdate` — 状态变更通知
- `vk_stt_result` — ASR 识别结果文本
- `vk_stt_status` — 状态 (idle/recording/processing/done/error)
- `vk_stt_partial` — 流式 partial 文本（Soniox）
- `vk_stt_timestamp` — 结果时间戳（用于去重）
- `vk_stt_error` — 具体错误信息（网络断开、API Key 无效、录音权限拒绝等）
- `vk_app_alive` — 主 App 后台心跳时间戳（键盘据此判断是否需要重新激活）

### 交互流程

**首次激活（仅一次）**:
1. 用户在任意 App 中使用 VoiceKey 键盘
2. 点击 🎤 → 键盘检查 `vk_app_alive` 心跳 → 主 App 未运行
3. URL Scheme 拉起主 App → 主 App 激活 AVAudioEngine + Background Audio
4. 主 App 自动返回宿主 App（`UIApplication` 切换或用户手动切回）
5. 屏幕顶部出现橙色圆点（麦克风正在使用）

**后续使用（无需跳转）**:
6. 用户点击 🎤 → 键盘通过 Darwin Notification 发送"开始录音"
7. 后台主 App 收到信号 → 开始 ASR 流式识别
8. ASR 结果实时写入 App Group → Darwin Notification 通知键盘
9. 键盘读取结果 → 显示在 DraftCanvas 或直接 `textDocumentProxy.insertText()`
10. 用户再次点击 🎤 → 停止录音 → 最终结果插入

**两种输出模式**:
- **直接插入模式**: 适合简短输入，ASR 结果直接插入宿主编辑框（类似 Wispr Flow）
- **DraftCanvas 模式**: 适合长文本或需要编辑的场景，先预览再确认插入

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

## M3: 架构重构 — 服务迁移 + 后台音频常驻

**目标**: 将所有音频/ASR 服务从键盘扩展迁移到主 App，建立双向 Darwin Notification IPC 通信，实现主 App 后台麦克风常驻。

**新建文件**:
- `Shared/VoiceKeyContract.swift` — App Group 通信协议（双 target 共享）
  - UserDefaults key 常量（状态/结果/命令/心跳）
  - `VKStatus` 枚举 (idle/recording/processing/done/error)
  - `VKCommand` 枚举 (startRecording/stopRecording/cancel)
  - Darwin Notification 发送/监听辅助方法
  - 读写便利方法
- `VoiceKey/Views/VoiceInputView.swift` — 主 App 录音界面（前台时可见，后台时隐藏但持续工作）
- `VoiceKey/Services/BackgroundAudioManager.swift` — 后台音频会话管理
  - 激活 `AVAudioSession` (category: `.playAndRecord`, mode: `.default`)
  - 维护 `AVAudioEngine` 在后台持续运行
  - 监听 Darwin Notification 接收键盘命令
  - 定时写入 `vk_app_alive` 心跳（每 5 秒）
  - 静默音频播放保持后台活跃（播放无声 PCM 防止系统挂起）

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
- `VoiceKeyApp.swift` — 注册 URL Scheme `voicekey://activate`；应用启动时激活 BackgroundAudioManager；处理前台/后台切换
- `KeyboardViewController.swift` — 移除所有 audio/STT 代码，改为：
  - 检查 `vk_app_alive` 心跳判断主 App 是否后台存活
  - 存活 → Darwin Notification 发命令（无跳转）
  - 不存活 → URL Scheme 激活主 App（仅首次/重新激活）
- `SettingsStore.swift` — 无结构改动（Keychain 迁移文档化）
- `Info.plist` (主 App) — 添加 `UIBackgroundModes: audio`、URL Scheme

**删除文件**:
- `VoiceKeyboard/Views/TranscriptionBannerView.swift` — 被 DraftCanvasView 替代

**架构决策**:
- **后台音频常驻**: 主 App 通过 `UIBackgroundModes: audio` + 静默音频播放在后台保持活跃。屏幕顶部会显示橙色圆点（麦克风指示器），这是 iOS 系统行为，无法避免也不应隐藏
- **双向 Darwin Notification**: 键盘→App 发命令（`vk_command`），App→键盘 发状态更新（`vk_sttUpdate`）。比 URL Scheme 快 100 倍以上
- **心跳检测**: 主 App 每 5 秒写入 `vk_app_alive` 时间戳。键盘检查时间戳 > 10 秒未更新则判定主 App 已被系统杀掉，触发 URL Scheme 重新激活
- **首次激活 + 自动返回**: URL Scheme 拉起主 App 后，延时 1.5s 自动调用 `openURL` 打开宿主 App 的 URL Scheme（或提示用户手动切回）
- **错误处理**: 主 App 出错时写入 `vk_stt_error`（含具体错误信息），键盘端显示具体错误提示 + 重试按钮
- **降级处理**: 键盘检测到主 App 未运行时显示"请手动打开 VoiceKey App"
- API Key 迁移到 Keychain 存储，通过 Keychain Sharing 跨 target 共享

**后台存活策略**:
- `AVAudioSession.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetooth])`
- 后台播放静默音频（极低频无声 PCM）防止系统挂起 AVAudioEngine
- 监听 `UIApplication.didEnterBackgroundNotification` → 确保音频会话保持活跃
- 监听 `AVAudioSession.interruptionNotification` → 中断恢复后重新激活
- 预计后台电池消耗：~1-2%/小时（参考 Wispr Flow 实测数据）

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

**交互设计（后台常驻模式下无需跳转 App）**:
1. 点击 🎤 → 键盘通过 Darwin Notification 向后台主 App 发送"开始录音"命令
2. 主 App 后台录音 + ASR → 实时写入 App Group
3. 键盘收到状态更新 → DraftCanvas 实时显示识别文本
4. 再次点击 🎤 → 发送"停止录音"命令 → 最终结果写入
5. 用户可在 DraftCanvas 中用键盘编辑文本
6. 点击 ✓ 确认 → 文本通过 textDocumentProxy.insertText() 插入
7. 点击 ✕ 取消 → 清空 DraftCanvas
8. 主 App 出错 → DraftCanvas 显示具体错误 + 重试按钮

**两种输出模式**（用户可在设置中选择）:
- **DraftCanvas 模式**（默认）: 适合长文本或需要编辑的场景，先预览再确认插入
- **直接插入模式**: 适合简短输入，ASR 结果直接 `textDocumentProxy.insertText()` 插入宿主编辑框（类似 Wispr Flow 体验）

**首次激活流程**（仅一次，主 App 未运行时）:
1. 点击 🎤 → 键盘检测心跳 → 主 App 未运行
2. URL Scheme 拉起主 App → 激活后台音频 → 显示"已激活"
3. 用户切回宿主 App → 后续无需再跳转

支持 Markdown 简单高亮预留（如命令模式返回的修改部分用蓝色标注），为 M7 做准备

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
