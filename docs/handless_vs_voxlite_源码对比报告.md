# Handless 与当前工程 VoxLite 源码级对比报告

> 对比对象：
>
> - 当前工程：`/Users/wanghui/Code/voxlite`
> - 参考工程：`/Users/wanghui/Code/handless`

## 1. 结论先行

如果只看一句话：

- **VoxLite** 更像一个**围绕单一主链路深度打磨的原生 macOS MVP**：按住录音、松开处理、清洗、注入，架构收敛、依赖少、状态面小。
- **Handless** 更像一个**已经进入“桌面产品工程化”阶段的语音输入工作台**：不仅有录音与转写，还覆盖模型下载/切换、云端/实时 STT、后处理、历史、统计、CLI、托盘、配置迁移、导入导出等完整运行面。

因此，这不是简单的“谁更好”，而是两种明显不同的工程目标：

- VoxLite 优先优化：**极简主链路、原生收敛、低系统表面积**。
- Handless 优先优化：**功能包络、配置能力、生命周期管理、长期运营复杂度**。

本报告重点不在语言选型，而在**功能、实现、架构、性能取向、可扩展性**的细颗粒度对比，并提炼 Handless 值得借鉴的设计点。

---

## 2. 语言与技术栈（简要）

### VoxLite

- **语言/框架**：Swift 6 + SwiftUI + AppKit，原生 macOS。
- **架构风格**：显式分层 + 协议边界，核心模块拆分为 `Domain / Input / Core / Output / System / Feature / App`（`README.md:98-129`，`Sources/VoxLiteDomain/Protocols.swift:3-74`）。
- **核心特征**：不依赖大型跨平台运行时，核心依赖系统 API，例如 `CGEventTap`、`AVAudioRecorder`、`SpeechAnalyzer`、剪贴板与 HID 事件。

### Handless

- **语言/框架**：Rust（后端）+ Tauri（壳与桥接）+ React 19 + TypeScript + Zustand（前端状态）+ Tailwind/Radix（UI）（`package.json:27-98`，`src-tauri/src/lib.rs:1-23`）。
- **架构风格**：Tauri command/event 驱动 + Rust manager/coordinator 分层 + 前端 store 驱动 UI。
- **核心特征**：将高性能、系统级和音频/模型逻辑放在 Rust；将 UI、设置、模型管理界面放在 React/TS。

### 简短评价

- **VoxLite 的选型更适合**：极简、强原生、功能收敛的 macOS 工具。
- **Handless 的选型更适合**：功能面持续扩张、需要大量配置面与前后端协作的桌面产品。
- 但**技术栈本身并不直接等于架构优劣**。真正拉开差距的，是两边对“运行面复杂度”的承担程度。

---

## 3. 产品定位与范围边界差异

### VoxLite 的边界

VoxLite 代码和 README 都强烈体现出一个很明确的边界：

- 主链路必须始终稳定：**按住热键录音 → 松开后处理 → 文本注入焦点输入框**（`README.md:232-239`）。
- 设计目标是轻量、端侧优先、零第三方依赖、低内存占用（`README.md:31-37`）。
- 主流程围绕 `VoicePipeline` 集中实现，状态机也非常克制（`Sources/VoxLiteCore/VoicePipeline.swift:41-176`，`Sources/VoxLiteDomain/VoxStateMachine.swift:3-36`）。

这说明 VoxLite 不是通用语音平台，而是一个**收敛到输入法式主链路的系统级工具**。

### Handless 的边界

Handless 的范围明显更大：

- 本地模型 + 云端 STT + 实时流式 STT（`README.md:25-33`，`src-tauri/src/cloud_stt/mod.rs:3-87`）。
- LLM 后处理、提示词管理、历史、统计、模型下载与卸载、CLI、系统托盘、调试面板、导入导出（`src-tauri/src/lib.rs:111-264`，`src-tauri/src/settings.rs:323-435`，`src/components/settings/history/HistorySettings.tsx:64-347`，`src/components/settings/post-processing/PostProcessingSettings.tsx:875-903`）。

它更像一个**语音输入工作台 / 可配置语音中台产品**，而不是单功能输入助手。

### 这一点对后续判断非常重要

很多“Handless 功能更多”的现象，本质上不是单点实现更强，而是**产品包络更大**。报告后续所有结论都应在这个前提下理解。

---

## 4. 功能层面对比

### 4.1 核心主链路功能

| 维度 | VoxLite | Handless |
|---|---|---|
| 触发方式 | Fn / 自定义快捷键，按住录音、松开处理（`README.md:33-34`，`HotKeyMonitor.swift:48-169`） | 多快捷键绑定，支持 Hold / Toggle / HoldOrToggle（`settings.rs:9-17`，`transcription_coordinator.rs:86-150`） |
| 录音 | 基于 `AVAudioRecorder` 的临时录音文件（`AudioCaptureService.swift:38-60`） | 长开/按需两种模式，设备选择、静音、stream tap、VAD 协同（`audio.rs:157-498`） |
| 转写 | 端侧优先，失败再走网络 fallback；也支持配置远端 STT（`SpeechTranscriber.swift:90-146`，`AppViewModel.swift:618-643`） | 本地模型 / 云端 STT / 实时流式 STT 三套路径并存（`transcription.rs:372-485`，`actions.rs:124-190`） |
| 清洗/后处理 | 上下文分类 + 技能模板 + Foundation Model / 远端 LLM / fallback 规则清洗（`TextCleaner.swift:79-202`，`AppViewModel.swift:648-679`） | 独立的 LLM 后处理系统，provider、model、prompt、pricing、统计齐全（`post-processing/PostProcessingSettings.tsx:203-903`） |
| 注入 | 剪贴板替身 + `Cmd+V` + 恢复原剪贴板（`ClipboardTextInjector.swift:39-57`） | 支持多种 paste/typing 策略、auto submit、外部脚本等（`settings.rs:184-201`, `240-248`, `371-385`） |

### 4.2 运行期能力

| 维度 | VoxLite | Handless |
|---|---|---|
| 历史 | JSON 历史，记录源文/输出文/技能/应用等（`LocalStores.swift:4-31`，`AppViewModel.swift:548-566`） | SQLite 历史 + WAV 文件 + 收藏 + 分页 + 回放 + 统计（`history.rs:21-45`, `218-276`, `431-680`） |
| 模型管理 | 提供本地/远端 STT 与 LLM 设置，但没有本地模型下载/库管理体系（`ModelSettingsView.swift:34-310`） | 本地模型库、下载、断点续传、解压、删除、自动选型、自定义模型发现（`model.rs:57-1210`） |
| 实时流式识别 | 无独立流式识别链路 | 有 realtime session、流式文本回写 overlay、失败后回退 batch（`actions.rs:132-190`, `305-349`） |
| CLI / 外部控制 | 无 | 有 CLI flags 和单实例远程控制（`README.md:40-61`，`lib.rs:441-452`） |
| 系统托盘/Overlay | 有菜单栏 UI，但运行态 UI 较轻 | Tray、overlay、窗口隐藏/恢复、更新检查、取消等更完整（`lib.rs:177-264`，`RecordingOverlay.tsx:79-553`） |

### 4.3 功能结论

- **Handless 在功能广度上明显领先**，尤其是模型生命周期、云服务接入、流式识别、历史与统计、导入导出、CLI、设置深度。
- **VoxLite 在核心闭环上更聚焦**，没有把复杂度扩散到大量二级能力上。

这意味着：

- 如果目标是“快速、稳定、低干扰地把语音塞进当前输入框”，VoxLite 的边界更清晰。
- 如果目标是“把语音输入做成一个可以调优、回看、扩展、运维的完整桌面产品”，Handless 明显更成熟。

---

## 5. 关键实现链路对比

## 5.1 热键与输入触发

### VoxLite

`HotKeyMonitor` 用 `CGEvent.tapCreate(..., .listenOnly, ...)` 监听 `flagsChanged / keyDown / keyUp`，并区分 Fn 模式与自定义按键模式（`HotKeyMonitor.swift:48-169`）。

优点：

- 实现短、直接、容易验证。
- `listenOnly` 模式减少破坏系统快捷键的风险。
- Fn 特殊处理逻辑很清晰（`HotKeyMonitor.swift:111-124`）。

不足：

- 模式单一，交互语义基本围绕“按住/松开”组织。
- 没有像 Handless 那样抽象出多 activation mode。

### Handless

Handless 把热键触发语义放在 `TranscriptionCoordinator`，支持 `Hold / Toggle / HoldOrToggle` 三种模式，并在单独线程串行化处理输入事件（`transcription_coordinator.rs:44-49`, `67-177`）。

优点：

- 不只是监听输入，而是把“按下/抬起如何解释”为显式状态机。
- `DEBOUNCE`、`HOLD_THRESHOLD` 等控制点清楚（`transcription_coordinator.rs:16-19`）。
- 能统一处理键盘、信号、overlay confirm、cancel 等来源，减少竞态。

结论：

- **VoxLite 的输入监听更轻、更窄、更像一个纯输入触发器**。
- **Handless 的输入层已经进化为“录音生命周期控制器”的前置入口**。

## 5.2 录音与音频采集

### VoxLite

`AudioCaptureService` 使用 `AVAudioRecorder` 写入临时 `.m4a`，停止后不直接回传 PCM，而是把 `file://路径|elapsedMs` 编码进 `Data` 再交给 pipeline 解析（`AudioCaptureService.swift:38-91`，`VoicePipeline.swift:232-250`）。

优点：

- 链路简单。
- 临时文件形式与后续基于文件的识别接口天然兼容。
- 带有 250ms restart cooldown 和 120ms minimum duration 保护（`AudioCaptureService.swift:13-24`, `31-37`, `71-83`）。

不足：

- `Data` 实际承载的是“字符串编码的文件路径+时长”，这是一个偏工程取巧的接口，不如显式结构体直观。
- 没有设备优先级、长开麦、stream tap、VAD 等更复杂的音频控制面。

### Handless

`AudioRecordingManager` 同时承担：

- always-on / on-demand 两种麦克风模式（`audio.rs:109-115`, `160-185`, `356-378`）；
- 设备选择、优先级、clamshell 模式麦克风切换（`audio.rs:190-252`）；
- 本地模型场景下为录音器挂接 Silero VAD + SmoothedVad（`audio.rs:117-140`, `291-313`）；
- streaming 时把音频帧直接送进 channel（`audio.rs:382-416`，`actions.rs:132-187`）；
- mute/unmute 和提示音配合（`audio.rs:256-277`，`actions.rs:193-224`, `262-267`）。

结论：

- **VoxLite 的录音实现是“足够完成主流程”的简单实现**。
- **Handless 的录音实现是完整的音频设备管理层**。

## 5.3 转写与推理路径

### VoxLite

`OnDeviceSpeechTranscriber` 的策略非常直接：

1. 权限检查；
2. locale 支持校验；
3. 先跑 on-device；
4. 失败后跑 network fallback；
5. 两条都失败则报错（`SpeechTranscriber.swift:90-146`）。

同时，`AppViewModel` 的 runtime bootstrap 已支持：

- 配置远端 STT provider；
- 从 Keychain 取 API key；
- 构造 `RemoteSpeechTranscriber`；
- 否则回退 `OnDeviceSpeechTranscriber`（`AppViewModel.swift:618-643`）。

这说明 VoxLite **不是纯端侧**，而是“端侧优先，远端可选”。

### Handless

`TranscriptionManager` 明确支持两大路径：

- **local**：Whisper / Parakeet / Moonshine / SenseVoice（`transcription.rs:13-29`, `39-45`, `488-646`）；
- **cloud**：多 provider 批量接口；另外还有 realtime path（`transcription.rs:394-447`，`cloud_stt/mod.rs:64-87`）。

并且它还实现了：

- 模型预加载（`lib.rs:145-152`）；
- idle unload / immediate unload（`transcription.rs:79-143`, `202-213`）；
- 引擎 panic 隔离，避免 poison 后整个系统卡死（`transcription.rs:507-641`）。

结论：

- VoxLite 的转写实现更像**单一策略链**。
- Handless 的转写实现更像**完整推理运行时**。

## 5.4 清洗 / 后处理

### VoxLite

`RuleBasedTextCleaner` 的真实能力需要分层看：

1. `ContextResolver` 的上下文识别其实很轻，只是按 bundleId 映射 `communication / development / writing / general`（`ContextResolver.swift:8-28`）。
2. `TextCleaner` 会基于技能模板构造 prompt，并调用 `PromptGenerating`，默认是 Apple Foundation Model，也可在 bootstrap 中切到远端 LLM（`TextCleaner.swift:79-202`，`AppViewModel.swift:648-679`）。
3. 如果生成失败，再 fallback 到规则清洗；而 fallback 的四类清洗目前本质上都只是 `normalizeSentence` + styleTag 区分（`TextCleaner.swift:135-161`）。

所以要客观地说：

- VoxLite 的“技能化清洗”方向是对的；
- 但当前上下文识别与 fallback 规则还比较轻，不应夸大成复杂上下文系统。

### Handless

Handless 的后处理是独立产品子系统：

- provider / model / API key / custom base URL / pricing / prompt 全可配置（`PostProcessingSettings.tsx:203-449`）；
- prompt 支持内置与自定义、增删改查、快捷键绑定关联、成本估算（`PostProcessingSettings.tsx:451-903`）；
- 运行时会记录后处理 stats 并发出事件（`actions.rs:371-410`）。

结论：

- VoxLite 的后处理更偏**主流程附属能力**。
- Handless 的后处理已经是**独立子产品**。

## 5.5 文本注入

### VoxLite

`ClipboardTextInjector` 是一个非常典型的“短、稳、够用”的实现：

1. 备份当前剪贴板；
2. 清空并写入目标文本；
3. 发送 `Cmd+V`；
4. 成功时延迟恢复备份；
5. 失败则返回 fallback 状态（`ClipboardTextInjector.swift:39-73`）。

优点是：

- 极其容易理解和验证；
- 与焦点输入框兼容性通常较高；
- 失败时文本不会丢失。

但这也意味着：

- 注入策略单一；
- 没有 direct typing、外部脚本、auto submit 等适配层。

### Handless

Handless 的注入策略从设置层就暴露为系统能力：

- `PasteMethod` 支持 `CtrlV / Direct / None / ShiftInsert / CtrlShiftV / ExternalScript`（`settings.rs:184-193`）；
- 还支持 `ClipboardHandling`、`AutoSubmitKey`、`TypingTool` 等组合配置（`settings.rs:195-211`, `309-319`）。

这说明 Handless 不是把“粘贴”视为单个实现细节，而是视为**跨应用兼容性层**。

---

## 6. 架构设计对比

## 6.1 VoxLite：严格分层 + 单主链路中心化

VoxLite 的设计亮点很明确：

- `Protocols.swift` 把 `AudioCaptureServing / SpeechTranscribing / TextCleaning / TextInjecting / PermissionManaging / MetricsServing` 等边界定义得很清晰（`Protocols.swift:3-74`）。
- `VoicePipeline` 把主链路编排集中在一个地方，读代码时几乎可以按业务顺序线性展开（`VoicePipeline.swift:79-176`）。
- `VoxStateMachine` 保持最小状态集合：`idle / recording / processing / injecting / done / failed`（`VoxStateMachine.swift:3-36`）。

这套结构的优点：

- 业务闭环非常清楚；
- 模块边界和测试边界天然明确；
- 对 MVP 主链路来说心智负担低。

但也有代价：

- 运行时控制面更多集中在 `AppViewModel`，它除了 UI 状态，还承担了 onboarding、history、skills、runtime reload、menu bar summary、settings、model selection 等大量职责（`AppViewModel.swift:9-739`）。
- 随着功能继续增加，`AppViewModel` 有进一步膨胀的风险。

## 6.2 Handless：Coordinator + Managers + Command/Event Bridge

Handless 的后端结构不是严格 clean architecture，而是更偏**产品工程导向的职责拆分**：

- `lib.rs` 负责应用装配与 Tauri plugin / command 注册（`lib.rs:111-264`, `278-592`）；
- `TranscriptionCoordinator` 专门解决录音生命周期的串行化与竞态（`transcription_coordinator.rs:44-49`, `55-253`）；
- `AudioRecordingManager / TranscriptionManager / ModelManager / HistoryManager` 各自负责一类长期状态（`lib.rs:117-143`）；
- 前端通过 `commands::*` 和事件系统与后端交互（`commands/mod.rs:13-253`，`modelStore.ts:233-353`，`settingsStore.ts:186-817`）。

优点：

- 面对“大量运行态状态 + 大量设置项 + 多来源事件”时，比单 ViewModel 更抗扩张。
- 各 manager 的职责比较稳定，适合持续加功能。
- Tauri command/event 让前后端边界清楚，UI 可独立演进。

缺点：

- 状态分散，理解成本更高；
- 需要同时理解 Rust 侧状态、Tauri 命令、前端 store 和组件树；
- 改动一个能力，经常需要穿透多层。

## 6.3 架构结论

- **VoxLite 胜在收敛与可读性**。
- **Handless 胜在长期承载复杂运行面的能力**。

如果未来 VoxLite 继续大幅增加模型管理、云端 provider、历史统计、外部控制、导入导出等功能，那么仅靠当前 `VoicePipeline + AppViewModel` 结构会逐渐吃力；届时更接近 Handless 的“运行时控制面拆分”会更有价值。

---

## 7. 数据生命周期与持久化对比

这是两边差异非常大、但容易被忽略的一点。

### VoxLite

- 历史、技能、设置都走本地 JSON 文件（`LocalStores.swift:4-239`）。
- 录音使用临时文件，pipeline 在解析后就 `removeItem` 删除（`VoicePipeline.swift:97-99`）。
- README 明确强调“不持久化原始音频”（`README.md:379-385`）。

这体现的是：

- 数据模型简单；
- 实现维护成本低；
- 隐私姿态更保守；
- 但统计分析、分页、迁移、跨版本演化能力较弱。

### Handless

- 历史用 SQLite，且有 migration 管理（`history.rs:14-45`, `118-155`）；
- 原始录音保存为 WAV 文件（`history.rs:218-276`）；
- 有 retention policy、分页、saved 状态、daily speaking stats、导入导出（`history.rs:278-680`，`commands/mod.rs:395-397`）。

这体现的是：

- 数据面成熟；
- 更适合长期积累与分析；
- 也意味着更重的隐私/存储/迁移责任。

### 结论

- **VoxLite 更像即时输入工具的数据策略**。
- **Handless 更像产品化工作台的数据策略**。

这个差异不能简单解读成谁先进，而是两种非常不同的产品立场。

---

## 8. 性能对比（基于架构的主观评估）

> 说明：这里不是实测 benchmark，而是基于源码结构、依赖面、状态复杂度做主观判断。

### 8.1 VoxLite 的性能取向

从代码结构看，VoxLite 有天然优势：

- 原生 Swift + 系统 API，运行链路短；
- 主链路对象少，跨层通信直接；
- 没有前后端桥接和 WebView UI 运行时负担；
- `VoicePipeline` 的时延采样非常明确，且有自检门禁思路（`VoicePipeline.swift:158-198`，`README.md:364-376`）。

因此主观判断：

- **在“单次按住说、松开写”的短链路场景里，VoxLite 理论上更容易做到低延迟、低资源占用和更稳定的响应曲线。**

### 8.2 Handless 的性能取向

Handless 在架构上做了大量性能相关设计：

- 模型 preload/unload（`lib.rs:145-152`，`transcription.rs:79-143`）；
- 本地模型与云端 provider 分流；
- realtime path 减少等待整段结束才出字；
- VAD 和多种模型让用户可在准确率/速度之间切换（`model.rs:80-399`）。

但与此同时，Handless 的系统成本也更高：

- Tauri + WebView + 前后端 IPC；
- 大量设置、事件、store、overlay、history、tray；
- 多 provider、多模型、多模式带来的状态分支。

因此主观判断：

- **Handless 的“最佳性能上限”可能很高，但它依赖更多前置条件（模型、配置、provider、机器环境）。**
- **Handless 的“平均复杂度成本”明显高于 VoxLite。**

### 8.3 性能结论

- 若只看**极简主链路效率和实现确定性**，VoxLite 更占优。
- 若看**多场景、多模型、多 provider 下的性能调优空间**，Handless 更强。
- 不能直接下结论说某一方“性能一定更好”；更准确的说法是：
  - VoxLite：**低复杂度、低开销、低变异性**；
  - Handless：**高能力上限、高调优空间，也有更高复杂度成本**。

---

## 9. 可扩展性对比

## 9.1 VoxLite 的扩展方式

VoxLite 的扩展点主要来自协议和设置：

- STT/LLM provider 可以通过 runtime bootstrap 切换（`AppViewModel.swift:602-739`）；
- 技能与技能匹配可扩展（`LocalStores.swift:46-195`，`AppViewModel.swift:132-215`）；
- Pipeline 各环节理论上都可用协议替换（`Protocols.swift:3-74`）。

但它的问题是：

- 一旦新增的不是“替换某个实现”，而是“新增一类运行时子系统”，就容易推高 `AppViewModel` 和 `settings/history` 的复杂度。
- 当前更适合“沿主链路纵向增强”，不太适合“横向长出很多新子产品”。

## 9.2 Handless 的扩展方式

Handless 的可扩展性明显更强，但成本也更高：

- 新 STT provider：加 cloud provider + command + settings + UI；
- 新本地模型：进 `ModelManager` 和 `TranscriptionManager`；
- 新设置项：进 Rust settings + command + TS store + UI；
- 新运行态能力：接入 coordinator / actions / overlay / tray / events。

这是一种**扩展面宽、但改动链条也长**的体系。

### 结论

- **VoxLite 的扩展成本更低，但扩展方向更窄。**
- **Handless 的扩展方向更广，但每次扩展的系统性成本更高。**

这也是为什么 Handless 更像平台化桌面产品，而 VoxLite 更像专注型工具。

---

## 10. Handless 比较优秀、值得借鉴的功能与架构设计点

这一节是本次对比最重要的输出。

## 10.1 一级优先级：最值得 VoxLite 借鉴

### 1）录音生命周期单独抽成 Coordinator

Handless 的 `TranscriptionCoordinator` 专门负责：

- hold / toggle / hold-or-toggle 语义解释；
- debounce；
- confirm / cancel / processing finished 统一串行化（`transcription_coordinator.rs:22-35`, `67-177`）。

**为什么优秀**：

- 它把“输入事件”和“业务阶段”之间的竞态显式建模了。
- 这比把所有逻辑堆进 ViewModel 或 pipeline 更抗复杂度增长。

**对 VoxLite 的启发**：

- 如果后续要支持更多触发模式、取消、中途确认、脚踏板/外部信号等输入源，建议把当前 `HotKeyMonitor + AppViewModel.handlePress/handleRelease` 的控制逻辑拆成独立 coordinator。

### 2）模型生命周期管理完整

Handless 的 `ModelManager + TranscriptionManager` 提供了：

- 模型下载、断点续传、解压、删除；
- 预加载、空闲卸载、立即卸载；
- 模型状态事件广播（`model.rs:716-1210`，`transcription.rs:156-365`）。

**为什么优秀**：

- 它不是简单“换模型”，而是把模型当作长期资产和运行时资源来管理。

**对 VoxLite 的启发**：

- 如果 VoxLite 后续要认真支持远端/本地多模型切换，不能只停留在设置项层面，最好补一层真正的模型生命周期管理，而不是只在 bootstrap 时切依赖。

### 3）数据面成熟：历史 + 统计 + retention + 迁移

Handless 的 `HistoryManager` 不只是保存记录，而是完整管理：

- SQLite migration；
- WAV 文件；
- speaking stats；
- retention policy；
- 分页与导入导出（`history.rs:21-45`, `218-680`）。

**为什么优秀**：

- 它让“历史”从 UI 附属功能变成了稳定的数据子系统。

**对 VoxLite 的启发**：

- 如果后续产品需要“复盘、统计、检索、导出”，JSON 文件会很快触顶；届时应尽早切换到更可演进的存储层。

## 10.2 二级优先级：中期可借鉴

### 4）把“注入策略”提升为配置层，而不是单实现细节

Handless 在设置中把 paste method、clipboard handling、auto submit、typing tool 都暴露为显式策略（`settings.rs:184-211`, `309-319`）。

**价值**：

- 对不同 app、不同输入框、不同用户习惯的兼容性更高。

**对 VoxLite 的启发**：

- 当前 `ClipboardTextInjector` 很适合 MVP，但若后续遇到更多目标应用兼容性问题，建议把“注入”升级为策略层，而不是继续在单个类里打补丁。

### 5）后处理系统产品化

Handless 的 prompt 管理、provider 切换、模型拉取、pricing、stats，已经形成完整闭环（`PostProcessingSettings.tsx:203-903`）。

**价值**：

- 让“后处理”从黑盒变成可运营、可调优、可观察的能力。

**对 VoxLite 的启发**：

- VoxLite 已经有技能和 LLM 生成器方向，但还缺少 prompt 运营、模型可视化、调用结果可观察等产品层支撑。

### 6）设置迁移与默认值补全机制

Handless 的 `settings.rs` 对旧字段迁移、新 provider 默认值补齐、prompt/provider 默认项同步做得很完整（`settings.rs:684-744`, `892-975`）。

**价值**：

- 对长期迭代非常关键，能降低升级时配置损坏和行为漂移风险。

**对 VoxLite 的启发**：

- 当前 JSON 设置存储已经足够，但如果配置项继续增长，建议尽早引入版本化迁移机制。

## 10.3 三级优先级：可按需吸收

### 7）CLI 与单实例远程控制

`--toggle-transcription / --cancel` 等能力，让 Handless 可被外部脚本和自动化系统驱动（`README.md:40-61`，`lib.rs:441-452`）。

### 8）Overlay 做成独立运行态界面系统

`RecordingOverlay.tsx` 不只是一个状态提示，而是支持流式文本、确认/取消、进度条、动态尺寸等（`RecordingOverlay.tsx:79-553`）。

### 9）前端状态管理与后端事件同步非常系统

`settingsStore.ts` 和 `modelStore.ts` 不只是缓存数据，而是管理 optimistic update、回滚、事件监听、后台状态同步（`settingsStore.ts:320-349`, `364-425`，`modelStore.ts:233-353`）。

---

## 11. VoxLite 当前相对更优秀的点

为了保持公平，也必须指出 VoxLite 的优势不是“少功能”，而是“少状态面”。

### 1）主链路更短、更直、更容易验证

`VoicePipeline` 的实现几乎可以一眼读完主业务过程（`VoicePipeline.swift:79-176`）。这对正确性、调试效率和回归验证都很友好。

### 2）原生分层更干净

`Protocols.swift` 的边界很明确，输入/核心/输出/系统的角色也更稳定（`Protocols.swift:3-74`）。

### 3）隐私与数据策略更保守

临时音频即删、轻持久化，更适合对本地存储敏感的输入场景（`VoicePipeline.swift:97-99`，`README.md:379-385`）。

### 4）实现确定性更高

VoxLite 运行路径少、provider 少、状态少，因此实际行为更容易保持一致。

---

## 12. 对当前工程的建议

如果目标仍然是“轻量 macOS 语音输入工具”，建议：

1. **保留 VoxLite 当前收敛架构，不要直接照搬 Handless 的全部功能面。**
2. **优先借鉴 Handless 的运行时控制设计，而不是 UI 规模。**
   - 首先引入 `Coordinator` 思路处理输入/取消/确认/不同触发模式。
3. **把模型切换从设置项提升到真正的生命周期管理。**
   - 至少补上 preload / unload / 状态事件。
4. **为设置和历史预留迁移机制。**
   - 现在仍可用 JSON，但要预留 schema 版本与迁移入口。
5. **把注入策略做成可插拔层。**
   - 继续保留 clipboard surrogate 作为默认，但为 direct typing / script-based 注入预留协议。
6. **如果未来要走“语音工作台”方向，再考虑引入更完整的数据层和设置层。**
   - 这时可以逐步向 Handless 的 manager/coordinator 风格靠近。

---

## 13. 最终评价

从源码层面看，Handless 的强不只是“功能多”，而是它已经形成了**完整桌面语音产品的运行时基础设施**：

- 有 coordinator；
- 有 manager；
- 有模型生命周期；
- 有 provider 抽象；
- 有历史与统计；
- 有配置迁移；
- 有前后端状态同步机制。

而 VoxLite 的强，则在于它把复杂问题收敛进了一个更短、更确定、更原生的闭环。

所以更准确的结论是：

- **Handless 更像“平台化、产品化的语音输入桌面应用”。**
- **VoxLite 更像“聚焦主链路体验的原生轻量语音输入工具”。**

如果当前工程的目标是继续保持轻巧，那么最值得学习的不是 Handless 的“全套功能”，而是它在**运行时协调、模型生命周期、数据与设置演进**上的设计方法。

---

## 附：本报告重点引用的源码文件

### VoxLite

- `README.md`
- `Sources/VoxLiteCore/VoicePipeline.swift`
- `Sources/VoxLiteInput/AudioCaptureService.swift`
- `Sources/VoxLiteInput/HotKeyMonitor.swift`
- `Sources/VoxLiteCore/SpeechTranscriber.swift`
- `Sources/VoxLiteCore/ContextResolver.swift`
- `Sources/VoxLiteCore/TextCleaner.swift`
- `Sources/VoxLiteOutput/ClipboardTextInjector.swift`
- `Sources/VoxLiteFeature/AppViewModel.swift`
- `Sources/VoxLiteSystem/LocalStores.swift`
- `Sources/VoxLiteDomain/Protocols.swift`
- `Sources/VoxLiteDomain/VoxStateMachine.swift`
- `Sources/VoxLiteApp/MainWindowView.swift`

### Handless

- `README.md`
- `package.json`
- `src-tauri/src/lib.rs`
- `src-tauri/src/transcription_coordinator.rs`
- `src-tauri/src/actions.rs`
- `src-tauri/src/managers/audio.rs`
- `src-tauri/src/managers/transcription.rs`
- `src-tauri/src/managers/model.rs`
- `src-tauri/src/managers/history.rs`
- `src-tauri/src/settings.rs`
- `src-tauri/src/cloud_stt/mod.rs`
- `src-tauri/src/commands/mod.rs`
- `src/App.tsx`
- `src/stores/settingsStore.ts`
- `src/stores/modelStore.ts`
- `src/components/settings/general/GeneralSettings.tsx`
- `src/components/settings/models/ModelsSettings.tsx`
- `src/components/settings/post-processing/PostProcessingSettings.tsx`
- `src/components/settings/history/HistorySettings.tsx`
- `src/components/onboarding/AccessibilityOnboarding.tsx`
- `src/overlay/RecordingOverlay.tsx`
