# VoiceKey — 从零开始的完整搭建指南

从 `git clone` 到 Xcode 编译运行的每一步操作。

---

## 前置条件

| 项目 | 要求 |
|------|------|
| macOS | Sequoia 或更新 |
| Xcode | 26.2+ |
| Apple Developer 账号 | 免费或付费均可（真机调试需付费账号） |
| Development Team | `EL6G8M5A96`（或替换为你自己的 Team ID） |

---

## 第 1 步：克隆代码仓库

```bash
git clone https://github.com/asterayx/VoiceKey.git
cd VoiceKey
```

---

## 第 2 步：用 Xcode 打开项目

```bash
open VoiceKey.xcodeproj
```

Xcode 打开后你会看到左侧导航栏只有 **VoiceKey** 一个 target。

---

## 第 3 步：将现有源文件添加到 VoiceKey 主 Target

当前 `project.pbxproj` 只注册了初始文件。需要把所有 VoiceKey 目录下的 `.swift` 文件加入主 target。

### 3.1 添加主 App 源文件

在 Xcode 左侧 **Project Navigator** 中：

1. 右键点击 **VoiceKey** 文件夹（黄色图标）→ **Add Files to "VoiceKey"...**
2. 在弹出的文件选择器中，导航到仓库根目录下的 `VoiceKey/` 文件夹
3. 选中以下文件（如果尚未在项目中）：
   - `VoiceKeyApp.swift`
   - `ContentView.swift`
   - `SettingsStore.swift`
4. 确保勾选 **Target Membership**: `VoiceKey` ✅
5. 点击 **Add**

> 如果文件已经显示在 Project Navigator 中则跳过此步。

---

## 第 4 步：为主 App 添加 App Group

1. 在 Project Navigator 中选中 **VoiceKey** 项目（蓝色图标）
2. 选择 **VoiceKey** target
3. 切换到 **Signing & Capabilities** 标签
4. 确认 **Team** 设置为你的开发团队
5. 点击 **+ Capability** → 搜索并添加 **App Groups**
6. 在 App Groups 中点击 **+** 添加：
   ```
   group.com.asterayx.voicekey
   ```

---

## 第 5 步：创建 VoiceKeyboard 扩展 Target

### 5.1 新建 Target

1. 菜单栏 **File → New → Target...**
2. 在模板列表中选择 **iOS → Custom Keyboard Extension**
3. 填写以下信息：
   - **Product Name**: `VoiceKeyboard`
   - **Bundle Identifier**: `com.asterayx.VoiceKey.VoiceKeyboard`（Xcode 会自动设置为主 App Bundle ID + `.VoiceKeyboard`）
   - **Language**: Swift
   - **Project**: VoiceKey
   - **Embed in Application**: VoiceKey
4. 点击 **Finish**
5. 弹出 **Activate "VoiceKeyboard" scheme?** → 点击 **Activate**

### 5.2 删除 Xcode 自动生成的文件

Xcode 会自动创建一个 `KeyboardViewController.swift`，我们需要删除它（因为代码仓库中已有）：

1. 在 Project Navigator 中找到 Xcode 新创建的 **VoiceKeyboard** 组
2. 找到自动生成的 `KeyboardViewController.swift`
3. 右键 → **Delete** → 选择 **Move to Trash**

---

## 第 6 步：将代码仓库中的文件添加到 VoiceKeyboard Target

### 6.1 添加 KeyboardViewController

1. 右键点击 Project Navigator 中的 **VoiceKeyboard** 组 → **Add Files to "VoiceKey"...**
2. 导航到仓库根目录的 `VoiceKeyboard/` 文件夹
3. 选中 `KeyboardViewController.swift`
4. 确保 **Target Membership** 只勾选 `VoiceKeyboard` ✅（不勾选 VoiceKey）
5. 点击 **Add**

### 6.2 添加 Services 目录

1. 右键 **VoiceKeyboard** 组 → **Add Files to "VoiceKey"...**
2. 导航到 `VoiceKeyboard/Services/` 文件夹
3. 选中**整个 `Services` 文件夹**（或选中以下所有文件）：
   - `StreamingSTTProvider.swift`
   - `STTProviderFactory.swift`
   - `SilenceDetector.swift`
   - `AudioCaptureService.swift`
   - `AudioBufferWriter.swift`
   - `SonioxStreamingService.swift`
   - `GroqSTTService.swift`
   - `CerebrasSTTService.swift`
   - `LanguageManager.swift`
4. 确保 **Target Membership** 只勾选 `VoiceKeyboard` ✅
5. 勾选 **Create groups**（不要选 Create folder references）
6. 点击 **Add**

### 6.3 添加 Views 目录

1. 右键 **VoiceKeyboard** 组 → **Add Files to "VoiceKey"...**
2. 导航到 `VoiceKeyboard/Views/` 文件夹
3. 选中**整个 `Views` 文件夹**（或选中以下所有文件）：
   - `KeyboardView.swift`
   - `TranscriptionBannerView.swift`
   - `CandidateBarView.swift`
4. **Target Membership**: `VoiceKeyboard` ✅
5. 勾选 **Create groups**
6. 点击 **Add**

### 6.4 添加 Input 目录

1. 右键 **VoiceKeyboard** 组 → **Add Files to "VoiceKey"...**
2. 导航到 `VoiceKeyboard/Input/` 文件夹
3. 选中 `PinyinEngine.swift`
4. **Target Membership**: `VoiceKeyboard` ✅
5. 勾选 **Create groups**
6. 点击 **Add**

---

## 第 7 步：设置 SettingsStore.swift 的双 Target 成员

`SettingsStore.swift` 必须同时属于 **VoiceKey** 和 **VoiceKeyboard** 两个 target：

1. 在 Project Navigator 中点击选中 `SettingsStore.swift`
2. 打开右侧 **File Inspector**（快捷键 `⌥⌘1`）
3. 在 **Target Membership** 部分，确保两个 target 都勾选：
   - [x] **VoiceKey**
   - [x] **VoiceKeyboard**

---

## 第 8 步：配置 VoiceKeyboard 的 Info.plist

### 8.1 使用仓库中的 Info.plist

代码仓库中已包含键盘扩展的 Info.plist（`VoiceKeyboard/Info.plist`）。

1. 首先，**删除 Xcode 自动生成的 Info.plist**（如果存在于 VoiceKeyboard 组中）
2. 右键 **VoiceKeyboard** 组 → **Add Files to "VoiceKey"...**
3. 选中仓库中的 `VoiceKeyboard/Info.plist`
4. **Target Membership**: `VoiceKeyboard` ✅
5. 点击 **Add**

### 8.2 设置 Info.plist 路径

1. 选中 **VoiceKey** 项目（蓝色图标）
2. 选择 **VoiceKeyboard** target
3. 切换到 **Build Settings** 标签
4. 搜索 `Info.plist`
5. 找到 **Info.plist File** → 设置值为：
   ```
   VoiceKeyboard/Info.plist
   ```

### 8.3 确认 Info.plist 内容

确保 Info.plist 中包含以下关键配置（仓库文件中已有）：

```xml
<key>NSExtension</key>
<dict>
    <key>NSExtensionAttributes</key>
    <dict>
        <key>RequestsOpenAccess</key>
        <true/>
        <key>PrimaryLanguage</key>
        <string>en-US</string>
    </dict>
    <key>NSExtensionPointIdentifier</key>
    <string>com.apple.keyboard-service</string>
    <key>NSExtensionPrincipalClass</key>
    <string>$(PRODUCT_MODULE_NAME).KeyboardViewController</string>
</dict>
```

---

## 第 9 步：为 VoiceKeyboard 添加 App Group

1. 选中 **VoiceKey** 项目
2. 选择 **VoiceKeyboard** target
3. 切换到 **Signing & Capabilities**
4. 确认 **Team** 与主 App 一致
5. 点击 **+ Capability** → **App Groups**
6. 添加相同的 Group：
   ```
   group.com.asterayx.voicekey
   ```

---

## 第 10 步：为 VoiceKeyboard 添加麦克风权限

在 **VoiceKeyboard** target 的 Build Settings 中添加麦克风使用说明：

1. 选中 **VoiceKeyboard** target → **Build Settings**
2. 搜索 `Privacy`
3. 找到 **Privacy - Microphone Usage Description**
4. 填入：
   ```
   VoiceKey needs microphone access for speech-to-text input.
   ```

> 或者，如果你使用的是自定义 Info.plist（第 8 步），可以在 Info.plist 中添加：
> ```xml
> <key>NSMicrophoneUsageDescription</key>
> <string>VoiceKey needs microphone access for speech-to-text input.</string>
> ```

---

## 第 11 步：验证 Target 配置

### 11.1 VoiceKey 主 App Target

检查以下 Build Settings：

| 设置项 | 值 |
|--------|-----|
| Bundle Identifier | `com.asterayx.VoiceKey` |
| Development Team | 你的 Team ID |
| iOS Deployment Target | 18.0（或你的目标版本）|
| Swift Language Version | Swift 5 |
| Code Signing Style | Automatic |

### 11.2 VoiceKeyboard Extension Target

| 设置项 | 值 |
|--------|-----|
| Bundle Identifier | `com.asterayx.VoiceKey.VoiceKeyboard` |
| Development Team | 与主 App 一致 |
| iOS Deployment Target | 与主 App 一致 |
| Swift Language Version | Swift 5 |
| Info.plist File | `VoiceKeyboard/Info.plist` |

### 11.3 验证文件归属

在 Project Navigator 中，最终的文件结构应该如下：

```
VoiceKey (项目)
├── VoiceKey (主 App target)
│   ├── VoiceKeyApp.swift          → Target: VoiceKey
│   ├── ContentView.swift          → Target: VoiceKey
│   ├── SettingsStore.swift        → Target: VoiceKey + VoiceKeyboard (双 target)
│   └── Assets.xcassets
│
├── VoiceKeyboard (扩展 target)
│   ├── KeyboardViewController.swift    → Target: VoiceKeyboard
│   ├── Info.plist
│   ├── Services/
│   │   ├── StreamingSTTProvider.swift  → Target: VoiceKeyboard
│   │   ├── STTProviderFactory.swift    → Target: VoiceKeyboard
│   │   ├── SilenceDetector.swift       → Target: VoiceKeyboard
│   │   ├── AudioCaptureService.swift   → Target: VoiceKeyboard
│   │   ├── AudioBufferWriter.swift     → Target: VoiceKeyboard
│   │   ├── SonioxStreamingService.swift → Target: VoiceKeyboard
│   │   ├── GroqSTTService.swift        → Target: VoiceKeyboard
│   │   ├── CerebrasSTTService.swift    → Target: VoiceKeyboard
│   │   └── LanguageManager.swift       → Target: VoiceKeyboard
│   ├── Views/
│   │   ├── KeyboardView.swift          → Target: VoiceKeyboard
│   │   ├── TranscriptionBannerView.swift → Target: VoiceKeyboard
│   │   └── CandidateBarView.swift      → Target: VoiceKeyboard
│   └── Input/
│       └── PinyinEngine.swift          → Target: VoiceKeyboard
│
└── Products/
    ├── VoiceKey.app
    └── VoiceKeyboard.appex
```

要验证文件归属：点击任意 `.swift` 文件 → 右侧 File Inspector → 检查 **Target Membership**。

---

## 第 12 步：创建共享 Scheme

为了让 CI 和命令行构建正常工作，需要创建共享 scheme：

1. 菜单栏 **Product → Scheme → Manage Schemes...**
2. 选中 **VoiceKey** scheme
3. 勾选右侧的 **Shared** 复选框
4. 如果 VoiceKeyboard 也有 scheme，同样勾选 **Shared**
5. 点击 **Close**

---

## 第 13 步：编译

### 13.1 选择模拟器编译（无需签名）

1. 在 Xcode 顶部工具栏，选择 scheme **VoiceKey**
2. 选择目标设备为 **iPhone 16**（或任意 iOS Simulator）
3. 按 **⌘B**（Build）

如果编译成功，你会在 Xcode 顶部看到 ✅ **Build Succeeded**。

### 13.2 常见编译错误排查

| 错误 | 原因 | 解决方法 |
|------|------|----------|
| `Cannot find type 'RecognitionLanguage' in scope` | `SettingsStore.swift` 未加入 VoiceKeyboard target | 在 File Inspector 中勾选 VoiceKeyboard target |
| `Cannot find type 'STTEngine' in scope` | 同上 | 同上 |
| `Use of undeclared type 'KeyboardViewController'` | `KeyboardViewController.swift` 未加入 VoiceKeyboard target | 在 File Inspector 中勾选 |
| `No such module 'AVFoundation'` | Extension target 缺少框架 | VoiceKeyboard target → General → Frameworks → 添加 AVFoundation |
| Signing 错误 | Team ID 不匹配 | 在 Signing & Capabilities 中选择正确的 Team |
| `Embedded binary is not signed with the same certificate as the parent app` | 主 App 和扩展的签名不一致 | 确保两个 target 使用相同的 Team 和 Automatic Signing |

---

## 第 14 步：在真机上测试

### 14.1 安装到设备

1. 用 USB 连接 iPhone
2. 在 Xcode 顶部选择你的设备
3. 按 **⌘R**（Run）
4. 首次运行可能需要在 iPhone 上信任开发者证书：
   **设置 → 通用 → VPN 与设备管理 → 开发者 App → 信任**

### 14.2 启用 VoiceKey 键盘

1. 打开 iPhone **设置**
2. **通用 → 键盘 → 键盘 → 添加新键盘...**
3. 在第三方键盘列表中找到 **VoiceKey**，点击添加
4. 点击已添加的 **VoiceKey** → 开启 **允许完全访问**（Allow Full Access）
   - 这是语音识别和网络功能必需的
5. 打开任意 App 的文本输入框
6. 长按地球图标 🌐 切换到 VoiceKey

### 14.3 配置 API Key

1. 打开 **VoiceKey** App（主程序）
2. 选择 STT 引擎（Soniox / Groq / Cerebras）
3. 输入对应的 API Key
4. 选择识别语言
5. 返回键盘使用

---

## 第 15 步：命令行编译（可选）

```bash
# 编译主 App（Simulator，无需签名）
xcodebuild build \
  -project VoiceKey.xcodeproj \
  -scheme VoiceKey \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO

# 如果编译成功，输出最后一行会显示 ** BUILD SUCCEEDED **
```

---

## 文件总览

```
VoiceKey/
├── .github/workflows/build.yml       # GitHub Actions CI
├── DEVELOPMENT_PLAN.md               # 开发计划 (M3–M10)
├── M1_Setup_Guide.md                 # 旧版 M1 搭建指南
├── SETUP_GUIDE.md                    # 本文档
│
├── VoiceKey.xcodeproj/               # Xcode 项目文件
│
├── VoiceKey/                         # 主 App 源码
│   ├── VoiceKeyApp.swift             # SwiftUI App 入口
│   ├── ContentView.swift             # 设置界面
│   ├── SettingsStore.swift           # App Group 共享设置 + 共享类型定义
│   └── Assets.xcassets/              # 图标和颜色
│
└── VoiceKeyboard/                    # 键盘扩展源码
    ├── KeyboardViewController.swift  # 扩展主控制器
    ├── Info.plist                     # 扩展配置
    ├── Services/
    │   ├── StreamingSTTProvider.swift # ASR 服务商协议
    │   ├── STTProviderFactory.swift   # 服务商工厂
    │   ├── SonioxStreamingService.swift # Soniox WebSocket 流式 ASR
    │   ├── GroqSTTService.swift       # Groq REST ASR
    │   ├── CerebrasSTTService.swift   # Cerebras REST ASR
    │   ├── AudioCaptureService.swift  # AVAudioEngine 音频采集
    │   ├── AudioBufferWriter.swift    # PCM→WAV 转换
    │   ├── SilenceDetector.swift      # 静音检测
    │   └── LanguageManager.swift      # 多语言映射
    ├── Views/
    │   ├── KeyboardView.swift         # QWERTY + 数字/符号键盘
    │   ├── TranscriptionBannerView.swift # 三态转录显示条
    │   └── CandidateBarView.swift     # 拼音候选字条
    └── Input/
        └── PinyinEngine.swift         # 拼音→汉字查找
```
