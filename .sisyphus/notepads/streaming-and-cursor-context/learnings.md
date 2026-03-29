# Learnings - streaming-and-cursor-context

## [2026-03-29T06:58:02] Plan Initialized
Session: ses_2c7f159b1ffeOIDaPccd17EMyF

### Project Context
- 技术栈：Swift 6 + SwiftUI + AppKit，macOS 15+，零第三方依赖
- 架构：严格分层 Input/Core/Output/System，层间仅通过 VoxLiteDomain 协议通信
- 主链路必须 100% 可用：按住 Fn 录音 → 松开处理 → 文本写入焦点输入框
- 测试驱动：先写失败测试，再写最小实现，最后重构保持测试全绿

### Key Architecture Decisions (From Plan)
1. **混合流式架构**：SFSpeechRecognizer 实时预览 + SpeechAnalyzer 最终高质量转写，两者并行运行
2. **上下文锁定策略**：录音 START 时读取光标上下文，录音过程中不再重新读取
3. **Feature Flag 模式**：StreamingMode enum (off/previewOnly/full)，默认 off，回退安全
4. **新增独立协议**：CursorContextReading / StreamingTranscribing，不修改现有协议签名
5. **AX 权限时机**：App 启动时请求，不在录音时请求
6. **光标上下文窗口**：±3 行或 500 字符（取较小者）
7. **AX 失败降级**：静默继续，log warning，不中断录音

### Technical Constraints
- 不修改 SpeechTranscribing / ContextResolving 现有签名
- 不引入第三方库
- 不实现智能标点或自动纠错
- 不支持多光标
- 不缓存历史上下文
- 不删除 AVAudioRecorder 路径（保留回退）

### Testing Requirements
- 全部现有 XCTest 在 StreamingMode.off 下必须通过
- 新功能必须有 TDD 覆盖
- 每个任务先写测试，再写实现

## [2026-03-29T07:06:44+00:00] Task 1: Domain层模型和协议扩展
Session: ses_2c7f159b1ffeOIDaPccd17EMyF

### 实现要点
- 新增 CursorContext / PartialTranscription / StreamingMode，均符合 Sendable 约束
- ContextEnrichment 扩展 cursorContext，且 isEmpty 同步纳入判断
- 新增 CursorContextReading / StreamingTranscribing 协议，未修改现有协议签名
- 测试使用 Swift Testing，协议 mock 覆盖读取上下文与流式转写

### 测试覆盖
- CursorContext 初始化与 Equatable
- PartialTranscription 初始化
- StreamingMode.allCases
- CursorContextReading / StreamingTranscribing mock 合规性

### 验证结果
- swift test --filter CursorContextTests: PASS
- swift build: PASS
- 协议签名完整性检查: PASS
- 全量测试: PASS

## [2026-03-29T07:xx:xx+00:00] Task 2: Feature Flag + StreamingMode 设置集成
Session: ses_2c7f159b1ffeOIDaPccd17EMyF

### 实现要点
- AppViewModel 新增 `@Published var streamingMode` + `@AppStorage` 持久化
- UserDefaults key: `"streamingMode"`，值为 `StreamingMode.rawValue`
- MainWindowView 设置页新增 Picker（`.radioGroup` 样式）
- `StreamingMode.displayName` 扩展提供用户友好标签

### 测试覆盖
- 默认值 `.off`
- UserDefaults 持久化
- 模式切换
- 状态机不触发录音

### 验证结果
- `swift test --filter StreamingModeTests`: PASS
- `swift build`: PASS
- 全量测试无回归: PASS

## [2026-03-29T08:xx:xx+00:00] Task 4: AX 权限请求集成到启动流程
Session: ses_2c7f159b1ffeOIDaPccd17EMyF

### 实现要点
- PermissionManager 新增 `checkAccessibilityPermission()` 与 `requestAccessibilityPermission()`
- App 启动流程已在 `VoxLiteApp.init()` 请求 AX 权限
- `VoicePipeline.startRecording()` 仅依赖麦克风 / 语音识别权限，AX 拒绝不阻断录音主链路

### 测试覆盖
- `testAXPermissionRequestAtLaunch`: 验证启动时调用 AX 请求接口
- `testAXPermissionDeniedGraceful`: 验证权限缺失时录音主流程仍可进入

### 验证结果
- swift build: PASS
- AXPermissionTests: PASS
- testAXPermissionDeniedGraceful: PASS

### 额外发现
- 当前工具链下 `swift-testing` 依赖会触发大量 deprecation warning；功能不受影响，但后续可考虑切回 toolchain 内置 Testing。

## [2026-03-29] Task 3: CursorContextReader 骨架 + TDD 测试用例

### 实现要点
- `AXCursorContextReader.readContext()` 骨架返回 `nil`，不调用任何 AX API
- 测试文件 9 个方法（≥8 要求）：3 个骨架降级验证（预期 PASS）+ 3 个 `withKnownIssue` 占位 + 1 个并发安全 + 1 个性能预算 + 1 个模型构造
- `withKnownIssue` 内调用 `async` 代码时必须用 `await withKnownIssue`（非 `withKnownIssue`），否则编译报 "expression is async but not marked with await"

### Swift 工具链注意事项
- `swift package clean` 后首次 `swift test` 需完整重编译（约 2-3 分钟），后续增量构建极快
- `.build/` 目录可能缓存旧版本（如 Swift 6.3 编译的 SwiftSyntax），导致 "module compiled with Swift 6.3 cannot be imported by Swift 6.2.4" 错误；解决方案：`swift package clean` 清理后重新构建

### 验证结果
- 测试方法数：9（≥8 ✅）
- testReadContextFromUnsupportedApp: PASS ✅
- testReadContextPermissionDenied: PASS ✅
- swift build: Build complete ✅

## [2026-03-29] Task 5: CursorContextReader AX API 完整实现

### 实现要点
- 完整 6 步 AX API 调用链：systemWide → focusedElement → valueAttribute → selectedText → selectedTextRange → contextWindow
- `AXUIElement` 不能用 `as?` 条件转型：CF 类型必须先检查 `rawFocused != nil`，再用 `rawFocused! as! AXUIElement`
- `kAXSelectedTextRangeAttribute` 返回 `AXValue` 包裹的 `CFRange`，必须用 `AXValueGetTypeID()` 验证类型后再用 `AXValueGetValue(_:_:_:)` 解包
- `NSWorkspace.shared` 需要 `import AppKit`（原骨架只有 `import Foundation`）
- 上下文窗口：行优先（±3 行），超 500 字符时改为字符截断

### 测试结果
- 9 tests passed，3 个 `withKnownIssue`（CI 环境无真实 TextEdit 焦点，记录 known issue 并通过）
- `withKnownIssue` 内含 async 调用必须用 `await withKnownIssue`

### Swift 注意事项
- CF 类型无法 `as?` 条件转换；`AXUIElement` 属于 `CFTypeRef` 体系
- `AXValueGetValue` 的第二个参数是 `.cfRange`，不是 `._cfRange`

### 提交
- Commit: `73c94e0`
- Branch: `develop`
- Message: `feat(input): implement AX API cursor context reading with full error handling`

## [2026-03-29] Task 10: LiveSpeechTranscriber

### 实现要点
- `SFSpeechRecognizer(locale:)` 可能返回 `nil`（不支持的 locale），需要 Optional 处理
- `requiresOnDeviceRecognition = true` + `shouldReportPartialResults = true` 是端侧实时转写的关键配置
- 每次 `startStreaming()` 前需先调用 `stopCurrentTask()` 清理旧状态，避免资源泄漏
- `AsyncStream` continuation 在 `recognitionTask` 回调中 yield `PartialTranscription`；`result.isFinal == true` 时调用 `continuation.finish()`
- 权限检查通过 `SFSpeechRecognizer.authorizationStatus()` 进行（非 `authorized` 时返回 `AsyncStream { $0.finish() }` 空流）
- `@unchecked Sendable`：SFSpeechRecognizer + SFSpeechRecognitionTask 不符合 Sendable，需要 `@unchecked Sendable`
- 信任度（confidence）从 `result.bestTranscription.segments.last?.confidence` 获取，类型为 `Float` 但转为 `Double` 存储
- Package.swift 中新增 `CoreTests` testTarget，无需 `linkerSettings` 添加 Speech.framework（SPM 自动链接系统框架）

### 测试覆盖（11 个测试）
- `testStartStreamingReturnsStream` - 验证返回 AsyncStream<PartialTranscription>
- `testStopStreamingBeforeStartDoesNotCrash` - stop 在 start 前调用不崩溃
- `testStopStreamingEndsStream` - stop 后 for await 立即退出
- `testAppendBufferBeforeStartDoesNotCrash` - appendBuffer 在 start 前不崩溃
- `testMultipleStartStopCyclesDoNotCrash` - 多次 start/stop 循环不崩溃
- `testDefaultLocaleInitializer` - 默认 zh-CN 与显式 zh-CN 均能创建流
- `testConformsToStreamingTranscribingProtocol` - 实现 StreamingTranscribing 协议
- `testPartialTranscriptionIsFinalSemantics` - PartialTranscription isFinal 语义验证
- `testStopStreamingIsAsyncAndAwaitable` - stopStreaming 可 await 调用
- `testAppendBufferAfterStartDoesNotCrash` - appendBuffer 在 start 后不崩溃
- `testCustomLocaleInitializer` - 自定义 locale（en-US）初始化正常

### 验证结果
- `swift test --filter LiveSpeechTranscriberTests`: 11 tests PASS ✅
- 全量测试 `swift test`: 132 tests PASS (3 known issues) ✅
- `swift build`: Build complete ✅
- `lsp_diagnostics`: ZERO errors ✅
- Commit: `c64e106` (develop)
