# VoiceKey 开发计划 (M3–M10)

## Context

VoiceKey 是一个 iOS 键盘扩展，将语音实时转换为文字输入。M1（设置+共享存储）和 M2（键盘UI+Soniox STT）已完成。用户提出了 15 项详细需求，涵盖多语言 ASR、多服务商 BYOK、LLM 后处理、语音命令编辑、自定义词典、历史记录、独立语音界面、性能优化等。本计划将这些需求组织为 M3–M10 共 8 个里程碑。

## iOS 键盘扩展关键约束

- **内存限制**: ~48-60MB，所有设计必须考虑内存预算
- **麦克风**: 需要 RequestsOpenAccess=YES + 用户授予 Full Access（已配置）
- **后台运行**: 不可能。键盘收起或锁屏后扩展被挂起，无法维持 WebSocket 或录音
- **textDocumentProxy**: selectedText 不可靠，仅能读取光标前约 300 字符
- **防熄屏**: 键盘扩展无法控制屏幕常亮；主 App 可通过 `UIApplication.shared.isIdleTimerDisabled = true` 实现

---

## M3: ASR 服务商抽象层 + 静音超时

**需求**: #2, #4, #9, #14

**目标**: 将 Soniox 硬编码解耦为可扩展的多服务商架构，并增加静音检测。

**新建文件**:
- `VoiceKeyboard/Services/StreamingSTTProvider.swift` — 协议：`connect()`, `disconnect()`, `sendAudio(Data)`, `finishAudio()` + `STTProviderDelegate`（`didUpdatePartial`, `didFinalizePart`, `didConnect`, `didDisconnect`, `didFail`）
- `VoiceKeyboard/Services/STTProviderFactory.swift` — 工厂，根据 SettingsStore 返回对应 provider
- `VoiceKeyboard/Services/SilenceDetector.swift` — PCM RMS 能量检测，可配置静音阈值和超时时间

**修改文件**:
- `SonioxStreamingService.swift` — 遵循 `StreamingSTTProvider` 协议
- `KeyboardViewController.swift` — 依赖协议而非具体类型；集成静音超时自动停止录音
- `AudioCaptureService.swift` — 在音频 tap 回调中调用 SilenceDetector
- `SettingsStore.swift` — 增加 `silenceTimeoutSeconds`（默认 3.0）、`webSocketIdleTimeoutSeconds`（默认 30.0）

**架构决策**:
- REST 类服务商（Groq/Cerebras）同样实现 `StreamingSTTProvider`，内部缓冲音频在 `finishAudio()` 时一次性发送
- **流式实时显示保留**：M2 已实现的 Soniox 流式 partial/final token 实时显示机制不变，抽象为 `STTProviderDelegate.didUpdatePartial` / `didFinalizePart` 回调。Soniox 保持真正流式显示；REST 类服务商（Groq/Cerebras）因 API 不支持 partial，录音期间显示 "Listening..."，结果一次性通过 `didFinalizePart` 返回
- 静音检测用 RMS 能量计算，不用 VAD 模型（节省内存）
- WebSocket 空闲超时：无音频发送超过 N 秒后断开，下次 sendAudio 时重连

**依赖**: 无（基于 M2）

---

## M4: Groq/Cerebras ASR + 多语言支持

**需求**: #1, #2, #4

**目标**: 新增 Groq 和 Cerebras ASR 服务商，扩展语言支持到 8 种语言。

**新建文件**:
- `VoiceKeyboard/Services/GroqSTTService.swift` — HTTP multipart 上传，缓冲 PCM→WAV 后发送到 `api.groq.com/openai/v1/audio/transcriptions`
- `VoiceKeyboard/Services/CerebrasSTTService.swift` — 同上，端点 `api.cerebras.ai/v1/audio/transcriptions`
- `VoiceKeyboard/Services/AudioBufferWriter.swift` — PCM→WAV 转换（44 字节头）
- `VoiceKeyboard/Services/LanguageManager.swift` — `RecognitionLanguage` 枚举（zhCN/zhYue/en/es/pt/fr/de/ja）+ 各服务商语言码映射

**修改文件**:
- `STTProviderFactory.swift` — 增加 `.groq`, `.cerebras` 分支
- `SettingsStore.swift` — 增加 `groqAPIKey`, `cerebrasAPIKey`；替换 `KeyboardLanguage` 为多语言数组 `activeLanguages: [RecognitionLanguage]`（用户选择+拖拽排序优先级）
- `SonioxStreamingService.swift` — 使用 LanguageManager 映射 language_hints
- `ContentView.swift` — Groq/Cerebras API Key 输入、语言选择 UI
- `KeyboardView.swift` — "中/EN" 改为语言循环切换按钮（点击循环，长按打开选择器）

**架构决策**:
- 非流式服务商（Groq/Cerebras）：录音期间 banner 仅显示 "Listening..."，完成后显示 "Processing..."
- 音频缓冲上限 120 秒（~3.8MB），在 48MB 预算内安全
- 中英混合：Soniox 用 `language_hints: ["zh","en"]`；Whisper 类用 `language: "zh"` + prompt 提示
- 粤语：Soniox 支持 `yue`，Whisper 类支持有限，UI 标注兼容性
- 模型列表获取：在主 App 调用 `/v1/models` 端点，结果存入 SettingsStore

**依赖**: M3

---

## M5: 键盘 UI 重构 + 数字符号 + 录音流程增强

**需求**: #5, #10, #15

**目标**: 重新设计键盘扩展行（识别行+mic+编辑按钮占位），增加数字/符号模式，完善录音状态机。

**修改文件**:
- `KeyboardView.swift` — 重大重构：
  - 增加数字/符号键盘模式（123 按钮功能实现）
  - Row 3 布局调整：🌐 | 123 | 语言 | 空格 | ✏️(编辑占位) | 🎤 | ⏎
  - Mic 按钮状态视觉：空闲(麦克风图标) → 录音中(红色停止图标) → 处理中(旋转图标)
- `TranscriptionBannerView.swift` — 重构为三态视图：
  - `.recording`: 实时显示 STT 流式结果（Soniox partial token 灰色斜体 + final token 黑色，M2 已实现，此处保留并适配新状态机）
  - `.processing`: 左→右填充进度条 + "正在处理..."（LLM 后处理阶段）
  - `.error`: 超时重试按钮 + 取消按钮
- `KeyboardViewController.swift` — 录音状态机：
  - idle → recording（点击 mic）→ processing（再次点击 mic，提交后处理）→ idle
  - 超时处理：ASR 超时显示原始文本；后处理超时显示 ASR 原始结果
  - 保存 `committedSTT` 到 UserDefaults 防崩溃丢失
- `RecordingProgressView.swift`（新）— 进度条组件

**架构决策**:
- 数字/符号键盘：两层（数字层 + 符号层），通过 `KeyboardMode` 枚举扩展
- 需求 #15（键盘重启后回到 app）：iOS 键盘扩展重启后自动出现在原来的文本框，无需特殊处理。关键是防止状态丢失——将进行中的文本持久化到 UserDefaults
- 进度条基于预估时间（LLM 平均响应时间的滑动平均值）

**依赖**: M3, M4

---

## M6: LLM 后处理引擎

**需求**: #3, #4, #5（后处理部分）

**目标**: 集成 LLM 对 ASR 输出进行后处理——去除填充词、多种输出风格。

**新建文件**:
- `VoiceKeyboard/Services/LLMProvider.swift` — 协议：`func process(systemPrompt: String, userContent: String) async throws -> String`
- `VoiceKeyboard/Services/OpenAICompatibleLLMService.swift` — 通用 OpenAI 兼容实现（覆盖 OpenAI/Groq/Cerebras/Grok(xAI)，它们都兼容 OpenAI API 格式）
- `VoiceKeyboard/Services/AnthropicLLMService.swift` — Anthropic Messages API 实现
- `VoiceKeyboard/Services/GeminiLLMService.swift` — Google Gemini API 实现
- `VoiceKeyboard/Services/LLMProviderFactory.swift` — 工厂
- `VoiceKeyboard/Services/PromptTemplates.swift` — 输出风格 Prompt 模板：
  - 聊天风格（口语化、保留语气）
  - 正式邮件风格
  - 备忘录/会议纪要风格
  - 文艺风格
  - 原始（仅去填充词）
  - 所有模板强制包含 "保持原始语言，不进行翻译" 指令

**修改文件**:
- `SettingsStore.swift` — LLM 服务商枚举（OpenAI/Anthropic/Gemini/Groq/Cerebras/Grok）、API Key、选中模型、默认输出风格
- `ContentView.swift` — LLM 配置区域：服务商选择、API Key、模型选择器（调用 API 获取列表）
- `KeyboardViewController.swift` — 在 STT 完成后调用 LLM 后处理流程
- `TranscriptionBannerView.swift` — 增加风格选择（小型 pill 按钮或长按 mic 选择）

**内置端点（无需用户填写）**:
| 服务商 | 端点 |
|--------|------|
| OpenAI | `api.openai.com/v1` |
| Anthropic | `api.anthropic.com/v1` |
| Google Gemini | `generativelanguage.googleapis.com/v1beta` |
| Groq | `api.groq.com/openai/v1` |
| Cerebras | `api.cerebras.ai/v1` |
| Grok (xAI) | `api.x.ai/v1` |

**架构决策**:
- OpenAI/Groq/Cerebras/Grok 都兼容 OpenAI Chat Completions API，用同一个 `OpenAICompatibleLLMService` 覆盖，只切换 base URL
- Anthropic 和 Gemini API 格式不同，各需独立实现
- LLM 响应超时 15 秒，超时后显示 ASR 原始文本
- 模型列表获取在主 App 执行，调用各服务商 `/models` 端点

**依赖**: M3, M5（UI 状态机）

---

## M7: 语音命令编辑模式

**需求**: #6, #7

**目标**: 实现编辑按钮 + 语音命令对选中文本的操作。

**新建文件**:
- `VoiceKeyboard/Services/CommandParser.swift` — 解析 STT 结果中的命令关键词：
  - "同音字 [上下文]" → `.homophone(context: String?)`
  - "转换成汉字数字" / "转换成中文数字" → `.toChineseNumber`
  - "转换成阿拉伯数字" → `.toArabicNumber`
  - "翻译成英文" → `.translateTo("en")`
  - "翻译成中文" → `.translateTo("zh")`
- `VoiceKeyboard/Services/EditCommandExecutor.swift` — 编排：命令文本 + 选中文本 → LLM → 结果
- `VoiceKeyboard/Services/HomophoneEngine.swift` — PinyinEngine 反向查找（字→拼音→所有同音字）

**修改文件**:
- `KeyboardView.swift` — 启用编辑按钮（M5 已占位）
- `KeyboardViewController.swift` — 编辑模式状态机：
  1. 用户在 app 中选中文本
  2. 点击编辑按钮 → 读取 `textDocumentProxy.selectedText`
  3. 若 selectedText 为空 → 回退读取剪贴板内容
  4. 开始录音（语音命令）
  5. 再次点击编辑按钮 → 停止录音，解析命令
  6. 匹配命令 → 发送 "命令+选中文本" 到 LLM
  7. 用结果替换选中文本
- `CandidateBarView.swift` — 复用显示同音字候选（同音字命令场景）

**文本选择+替换策略（两者结合方案）**:
1. 优先尝试 `textDocumentProxy.selectedText`
2. 若返回 nil/空 → 检查 `UIPasteboard.general.string`（提示用户先复制选中文本）
3. 若均为空 → Toast 提示 "请先选中文本或复制到剪贴板"
4. 替换操作：逐字 `deleteBackward()` 删除选中文本，再 `insertText()` 插入结果
5. 剪贴板路径时：直接 `insertText()` 插入结果（用户需手动删除原文）

**可行性评估**:
| 环节 | 可行性 | 说明 |
|------|--------|------|
| 读取选中文本 | ⚠️ 中 | selectedText 不可靠，剪贴板回退保底 |
| 语音命令识别 | ✅ 高 | 固定关键词，ASR 准确率足够 |
| 命令解析 | ✅ 高 | 关键词匹配，无需复杂 NLP |
| LLM 执行 | ✅ 高 | Prompt 明确，LLM 可靠处理 |
| 替换文本 | ⚠️ 中 | 逐字 deleteBackward 对长文本有延迟，建议限制 500 字符以内 |
| 同音字候选 | ✅ 高 | 复用 CandidateBarView + PinyinEngine 反查 |

**依赖**: M6（LLM 引擎）

---

## M8: 自定义词典 + 输入历史

**需求**: #8, #11

**目标**: 自定义词典提升识别准确度；记录每次输入的音频、文本和统计信息。

**新建文件**:
- `VoiceKey/Models/CustomDictionary.swift` — 词典模型，JSON 存储在 App Group 容器
- `VoiceKey/Models/InputRecord.swift` — 输入记录模型：原始音频文件路径、ASR 原文、后处理文本、字符数、ASR 耗时(ms)、LLM 耗时(ms)、时间戳
- `VoiceKey/Views/DictionaryView.swift` — 词典管理 UI（增删改）
- `VoiceKey/Views/HistoryView.swift` — 输入历史列表 + 详情（统计信息、重新处理）
- `VoiceKeyboard/Services/InputRecorder.swift` — 在键盘扩展中保存音频数据和记录元数据

**修改文件**:
- `ContentView.swift` — 导航到词典管理和历史记录页面
- `SonioxStreamingService.swift` / `GroqSTTService.swift` / `CerebrasSTTService.swift` — 传入 custom vocabulary/prompt hints
- `KeyboardViewController.swift` — 每次录音完成后保存记录
- `AudioCaptureService.swift` — 增加同步写入 PCM 数据到文件的选项

**架构决策**:
- 音频文件存储在 App Group shared container，键盘扩展写入，主 App 读取/管理
- 词典传递给 ASR：Soniox 用 `custom_vocabulary`；Whisper 类用 `prompt` 参数
- 历史记录的"重新处理"功能：读取已保存音频，用新选择的 ASR/LLM 模型重新处理
- 存储空间管理：自动清理 30 天以上的音频文件（可配置）；保留文本记录

**内存注意**: 音频写文件在后台线程进行，不额外占用内存

**依赖**: M6（需要 LLM 引擎支持重新处理功能）

---

## M9: 独立语音输入界面（主 App）

**需求**: #12, #13（替代方案）

**目标**: 在主 App 中提供独立的语音输入界面，支持长时间录音和防熄屏。

**新建文件**:
- `VoiceKey/Views/VoiceInputView.swift` — 全屏语音输入界面：
  - 大型录音按钮
  - 实时波形/音量显示
  - 实时 STT 文本滚动
  - 后处理风格选择
  - 完成后一键复制/分享
- `VoiceKey/Services/AppAudioService.swift` — 主 App 版音频捕获（可申请 Background Audio mode）
- `VoiceKey/Services/AppSTTCoordinator.swift` — 协调 ASR + LLM 处理流程

**修改文件**:
- `VoiceKeyApp.swift` — 注册 URL Scheme `voicekey://`，处理从键盘跳转
- `ContentView.swift` — 导航到独立语音输入界面
- `Info.plist`（主 App）— 添加 `UIBackgroundModes: audio`、URL Scheme

**防熄屏方案**:
- 主 App 录音期间设置 `UIApplication.shared.isIdleTimerDisabled = true`
- 录音结束后恢复 `isIdleTimerDisabled = false`
- 主 App 可申请 `UIBackgroundModes: audio`，在 app 进入后台时继续录音
- 键盘扩展中：当录音时间超过阈值（如 30 秒），提示用户 "切换到独立语音界面以获得更稳定体验"，通过 URL Scheme 跳转

**需求 #13 处理**: iOS 键盘扩展无法在锁屏后继续工作。替代方案是通过独立语音界面（主 App）实现长录音，主 App 支持后台音频和防熄屏。录音完成后文本存入 App Group 共享容器。

**依赖**: M4（ASR 服务商），M6（LLM 引擎）

---

## M10: 性能优化 + 连接管理 + 可扩展性

**需求**: #10, #14, #15, 以及为 ElevenLabs 等未来服务商预留扩展

**目标**: 全面优化网络、内存、电池消耗；完善连接生命周期管理。

**优化项**:

### 网络
- WebSocket 空闲断开策略（M3 已埋点，此处调优）：默认 30 秒无音频后断开，重连耗时 ~200ms
- HTTP 请求复用 `URLSession` 实例，避免重复 TLS 握手
- LLM 请求支持流式响应（SSE），减少首字延迟

### 内存
- 音频缓冲上限审计：确保 REST 类 ASR 缓冲 ≤ 4MB
- 键盘扩展启动时内存基线测量 + didReceiveMemoryWarning 处理
- 避免在扩展中加载不必要的资源（按需初始化服务）

### 电池
- 评估 WebSocket 长连接 vs 按需连接的电池消耗差异（通过 Instruments Energy Log 测量）
- 录音空闲超时后释放 AVAudioEngine
- LLM 请求完成后立即释放 URLSession

### 可扩展性
- `STTProviderFactory` 和 `LLMProviderFactory` 结构确保新增服务商只需：
  1. 新增一个 Service 文件实现协议
  2. 在 Factory 的 switch 中增加一个 case
  3. 在 SettingsStore 中增加 API Key 字段
- 为 ElevenLabs 等预留 `STTEngine` 和 `LLMEngine` 枚举值

**修改文件**: 全局审计和优化，涉及所有 Service 和 Controller 文件

**依赖**: M3–M9 全部完成后进行

---

## 里程碑依赖关系

```
M3 (ASR 抽象) ──→ M4 (多服务商+多语言) ──→ M5 (键盘 UI 重构)
       │                                         │
       └──→ M6 (LLM 后处理) ◄────────────────────┘
                   │
            ┌──────┼──────┐
            ▼      ▼      ▼
          M7     M8     M9
        (编辑)  (词典)  (独立UI)
                   │
                   ▼
                 M10 (性能优化)
```

## 验证方法

每个里程碑完成后：
1. **编译验证**: GitHub Actions CI 确保构建通过（已配置）
2. **模拟器测试**: 在 iOS Simulator 上验证 UI 交互
3. **真机测试**: 在 iPhone 上安装键盘扩展，验证：
   - 麦克风权限和录音功能
   - ASR 实时转录
   - LLM 后处理结果
   - 内存使用（Xcode Memory Gauge < 40MB）
4. **回归测试**: 验证前序里程碑功能未被破坏
