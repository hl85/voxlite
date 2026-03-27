# 和乐轻音 · Holoo VoxLite

> **按住说，松开写。** 一款极轻量的 macOS 系统级语音录入助手。只有 2M 的安装包，极致的轻量快捷！

[![Platform](https://img.shields.io/badge/platform-macOS%2015%2B-blue)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/swift-6.0-orange)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-green)](#)

---

## 目录

- [产品简介](#产品简介)
- [核心功能](#核心功能)
- [系统要求](#系统要求)
- [快速开始](#快速开始)
- [项目架构](#项目架构)
- [模块说明](#模块说明)
- [运行与自检](#运行与自检)
- [Beta 打包](#beta-打包)
- [开发规范](#开发规范)
- [PR 流程规范](#pr-流程规范)
- [性能指标](#性能指标)
- [隐私声明](#隐私声明)
- [文档索引](#文档索引)

---

## 产品简介

**和乐轻音（Holoo VoxLite）** 是一款常驻 macOS 状态栏的极简语音录入工具，专为高频文字输入场景设计。

- **无感触发**：按住 `Fn`（或自定义快捷键）开始录音，松开即自动处理
- **智能写入**：识别当前前台应用场景，清洗后直接写入焦点输入框
- **端侧优先**：默认使用设备端语音识别，断网也可用
- **极度轻量**：安装包目标 < 10MB，空闲内存 < 150MB，零第三方依赖


## 核心功能

| 功能 | 说明 |
|---|---|
| 全局热键监听 | `CGEventTap + flagsChanged`，支持 Fn 及自定义组合键 |
| 端侧语音识别 | 基于 `SpeechAnalyzer`（macOS 26+），优先设备端，自动降级 |
| 场景感知清洗 | 识别前台 App，按沟通 / 开发 / 写作三路由清洗输出 |
| 剪贴板注入 | 快照备份 → 写入 → 模拟 `Cmd+V` → 50ms 恢复原剪贴板 |
| 注入失败回退 | 自动复制到剪贴板并提示 `Cmd+V` 手动粘贴 |
| 权限引导 | 分步引导麦克风 / 辅助功能 / 语音识别三项权限 |
| 超时重试 | 单次处理 > 3s 触发超时，支持一键重试 |
| 性能采样 | 实时展示 CPU / 内存 / P50 / P95 时延 |

---

## 系统要求

- **macOS 15.0+**（语音识别引擎需 macOS 26+）
- **Xcode 26+** / Swift 6.0
- 所需系统权限：
  - 麦克风
  - 辅助功能（Accessibility）
  - 语音识别

---

## 快速开始

### 1. 克隆并构建

```bash
git clone git@github.com:hl85/voxlite.git
cd voxlite
swift build --disable-sandbox
```

### 2. 安装本地 Git Hooks（新成员必做）

```bash
bash scripts/install_hooks.sh
```

### 3. 运行自检

```bash
swift run --disable-sandbox VoxLiteSelfCheck
# 输出 SELF_CHECK_OK 表示通过
```

### 4. 通过 Xcode 运行 App

```bash
open voxlite.xcodeproj
# 选择 voxlite scheme → Run
```


---

## 项目架构

```
voxlite/
├── Sources/
│   ├── VoxLiteDomain/          # 领域模型、协议、状态机、错误码
│   ├── VoxLiteInput/           # 热键监听、音频采集
│   ├── VoxLiteCore/            # 语音识别、场景识别、文本清洗、主流水线
│   ├── VoxLiteOutput/          # 文本注入、剪贴板回退
│   ├── VoxLiteSystem/          # 权限管理、日志、指标、性能采样
│   ├── VoxLiteFeature/         # App 状态机、ViewModel、启动引导
│   ├── VoxLiteApp/             # 菜单栏 UI 入口
│   └── VoxLiteSelfCheck/       # 自检链路（CI 质量门禁）
├── docs/                       # 需求、UX、WBS、测试清单、GitFlow
├── scripts/                    # 构建、打包、公证、Hooks 工具脚本
├── .githooks/                  # 本地 Git Hooks
├── .github/workflows/          # GitHub Actions CI
└── voxlite.xcodeproj           # Xcode 工程（链接 SPM Package）
```

### 分层依赖关系

```
VoxLiteApp
    └── VoxLiteFeature
            ├── VoxLiteInput    ──→ VoxLiteDomain
            ├── VoxLiteCore     ──→ VoxLiteDomain + VoxLiteSystem
            ├── VoxLiteOutput   ──→ VoxLiteDomain + VoxLiteSystem
            └── VoxLiteSystem   ──→ VoxLiteDomain
```

> 各层只通过 `VoxLiteDomain` 中定义的协议通信，**禁止跨层直接调用**。


---

## 模块说明

### VoxLiteDomain
核心契约层。定义全局复用的数据结构、协议、状态机与错误码。

- `VoxStateMachine`：`Idle → Recording → Processing → Injecting → Done / Failed`
- `Models.swift`：`ProcessResult`、`CleanResult`、`InjectResult` 等（均含 `success / errorCode / latencyMs`）
- `Protocols.swift`：`AudioCaptureServing`、`SpeechTranscribing`、`TextInjecting` 等核心协议
- `HotKeySettings.swift`：热键配置持久化（UserDefaults）

### VoxLiteInput
- `HotKeyMonitor`：基于 `CGEventTap` 的全局热键监听，支持 Fn 及自定义组合键，listen-only 不破坏系统快捷键
- `AudioCaptureService`：`AVAudioRecorder` 录音会话，含防抖（250ms 冷却）、最短录音保护（120ms）

### VoxLiteCore
- `OnDeviceSpeechTranscriber`：调用 `SpeechAnalyzer`（macOS 26+），端侧优先，失败自动网络降级
- `FrontmostContextResolver`：读取前台 App `bundleId`，映射为 `communication / development / writing / general`
- `RuleBasedTextCleaner`：按场景三路由清洗，输出风格可预测
- `VoicePipeline`：编排完整主链路，含超时控制、重试策略、降级回退

### VoxLiteOutput
- `ClipboardTextInjector`：剪贴板快照替身注入；失败时保留文本并上报 `usedClipboardFallback`

### VoxLiteSystem
- `PermissionManager`：麦克风 / 辅助功能 / 语音识别权限管理与授权引导
- `ConsoleLogger`：基于 `os.Logger`，日志不记录原始语音与完整文本
- `InMemoryMetrics`：事件埋点与 P50/P95 百分位计算
- `PerformanceSampler`：实时采样 CPU 与驻留内存

### VoxLiteFeature
- `AppViewModel`：App 级状态机，协调 Pipeline、权限、热键、UI 状态
- `VoxLiteFeatureBootstrap`：默认依赖组装入口

### VoxLiteSelfCheck
完整的自检链路，覆盖：状态机迁移、三场景清洗路由、Pipeline 降级回退、权限错误映射、重试与超时、Fn 边界、注入回退、App 状态机、性能门禁（P50/P95）。

---

## 运行与自检

```bash
# 构建
swift build --disable-sandbox

# 运行自检（CI 质量门禁）
swift run --disable-sandbox VoxLiteSelfCheck
# ✅ 通过标志：终端输出 SELF_CHECK_OK

# 运行 App（需在 Xcode 中以便获取系统权限）
open voxlite.xcodeproj
```


---

## Beta 打包

### 前置准备

1. 安装完整 Xcode（非 Command Line Tools）
2. 复制并填写导出配置：
   ```bash
   cp scripts/beta_export_options.plist.template scripts/beta_export_options.plist
   # 填入你的 Team ID
   ```
3. 存储公证凭据：
   ```bash
   xcrun notarytool store-credentials AC_NOTARY \
     --apple-id your@email.com \
     --team-id YOUR_TEAM_ID \
     --password "your-app-specific-password"
   ```

### 执行打包

```bash
# 预检（验证工具链、凭据、自检全通过）
chmod +x scripts/beta_preflight_check.sh
scripts/beta_preflight_check.sh

# 归档 + 公证 + 装订
chmod +x scripts/beta_archive_and_notarize.sh
BUILD_MODE=package scripts/beta_archive_and_notarize.sh
```

| 环境变量 | 默认值 | 说明 |
|---|---|---|
| `BUILD_MODE` | `auto` | `project`（用 xcodeproj）/ `package`（用 SPM）/ `auto`（自动检测） |
| `SCHEME` | `voxlite` | Xcode scheme 名称 |
| `NOTARY_PROFILE` | `AC_NOTARY` | notarytool keychain profile 名称 |
| `ARCHIVE_PATH` | `build/VoxLiteApp.xcarchive` | 归档输出路径 |

---

## 开发规范

### 代码生成原则（摘自 `.trae/rules/rules.md`）

1. 仅实现 macOS MVP，技术栈固定为 **Swift 6 + SwiftUI + AppKit**，禁止引入第三方库
2. 主链路必须始终可用：**按住 Fn 录音 → 松开处理 → 文本写入焦点输入框**
3. 架构严格分层 `Input / Core / Output / System`，禁止跨层直接调用
4. 事件监听使用 `CGEventTap + flagsChanged`，不得破坏系统原生快捷键
5. 语音识别默认端侧（`requiresOnDeviceRecognition = true`），网络不可用仍保证可用
6. 文本清洗必须走"沟通 / 开发 / 写作"三路由，输出稳定、可预测、可复现
7. 文本注入优先剪贴板快照替身；失败时必须回退并保证文本不丢失
8. 所有核心结果对象统一包含 `success`、`errorCode`、`latencyMs`
9. **严格测试驱动**：先写失败测试，再写最小实现，最后重构并保持测试全绿
10. 任何新增逻辑必须附带对应测试；缺陷修复必须先补可复现的回归测试

### Commit Message 规范

格式：`<type>(<scope>): <描述>`

| type | 适用场景 |
|---|---|
| `feat` | 新功能 |
| `fix` | 缺陷修复（必须先有回归测试） |
| `test` | 新增或修改测试 |
| `refactor` | 重构（不改变行为） |
| `perf` | 性能优化 |
| `chore` | 构建 / 工具链 / 依赖 |
| `docs` | 文档 |
| `ci` | CI/CD 配置 |

scope 示例：`input`、`core`、`output`、`system`、`feature`、`pipeline`

```
feat(input): support custom hotkey configuration
fix(output): restore clipboard after injection failure
test(pipeline): add regression for timeout retry exhaustion
perf(core): reduce transcription cold start latency
```


---

## PR 流程规范

### 分支模型

```
main          ── 仅接受 release/* 和 hotfix/* 合入，每次合入打语义化 Tag
develop       ── 日常集成主线，所有 feature/* 合入此处
feature/*     ── 从 develop 拉取，合回 develop
release/*     ── 从 develop 拉取，合回 main 和 develop
hotfix/*      ── 从 main 拉取，合回 main 和 develop
```

详细策略见 [`docs/GITFLOW.md`](docs/GITFLOW.md)。

### 新功能开发流程

```bash
# 1. 从最新 develop 拉取功能分支
git checkout develop && git pull voxlite develop
git checkout -b feature/VOX-42-your-feature-name

# 2. 开发 + 提交（必须符合 Conventional Commits 格式）
git commit -m "feat(input): support custom hotkey configuration"

# 3. 推送前本地自检会自动触发（pre-push hook）
git push voxlite feature/VOX-42-your-feature-name

# 4. 在 GitHub 上向 develop 提 Pull Request
```

### 热修复流程

```bash
# 1. 从 main 拉取 hotfix 分支
git checkout main && git pull voxlite main
git checkout -b hotfix/VOX-99-critical-bug-description

# 2. 先补回归测试，再提交修复
git commit -m "test(output): add regression for clipboard restore failure"
git commit -m "fix(output): restore clipboard correctly after inject timeout"

# 3. 向 main 提 PR，合入后同步合回 develop
git push voxlite hotfix/VOX-99-critical-bug-description
```

### PR 准入规则

提交 PR 前请确认以下全部满足：

- [ ] 本地 `swift build --disable-sandbox` 通过
- [ ] `swift run --disable-sandbox VoxLiteSelfCheck` 输出 `SELF_CHECK_OK`
- [ ] 新功能 / 修复附带了对应测试
- [ ] Commit message 符合 `<type>(<scope>): <描述>` 格式
- [ ] PR 描述填写了**改动原因**、**测试方式**、**截图或日志**（如适用）
- [ ] 已 rebase 到目标分支最新提交（无多余 merge commit）

### CI 自动检查项

每个 PR 会自动触发以下 GitHub Actions 检查，全部通过才可合入：

| 检查项 | 说明 |
|---|---|
| **Lint Commit Messages** | 校验所有 commit message 格式 |
| **Build & Self Check** | `swift build` + `VoxLiteSelfCheck` |
| **Branch Policy Guard** | 校验合入目标分支是否合规 |

### 分支保护规则

| 分支 | Reviewer 数 | CI 要求 | 其他 |
|---|---|---|---|
| `main` | **2 人**批准 | 全部通过 | 线性历史、禁 force push、管理员也须遵守 |
| `develop` | **1 人**批准 | Build & Self Check 通过 | 禁 force push |

> 首次配置远端分支保护：`REPO=hl85/voxlite bash scripts/setup_branch_protection.sh`

### 本地 Hooks 安装

团队成员克隆仓库后**必须执行**：

```bash
bash scripts/install_hooks.sh
```

安装后生效的保护：

| Hook | 触发时机 | 作用 |
|---|---|---|
| `pre-commit` | `git commit` | 拦截直接向 `main` 提交 |
| `commit-msg` | `git commit` | 校验 Conventional Commits 格式 |
| `pre-push` | `git push` | 推送到 `main` / `develop` 前自动跑构建和自检 |


---

## 性能指标

| 指标 | 目标 | 采样方式 |
|---|---|---|
| 状态反馈延迟 | < 100ms | 触发热键到 UI 状态变更 |
| 端到端时延 P50 | < 1,000ms | 松开热键到文本写入完成 |
| 端到端时延 P95 | < 1,800ms | 同上，95 分位统计 |
| 空闲 CPU | < 3% | 空闲态 10 分钟采样 |
| 录音峰值 CPU | < 25% | 连续短语录入采样 |
| 空闲驻留内存 | < 150MB | 常驻空闲态观测 |

性能门禁已内置于 `VoxLiteSelfCheck`（20 次连续 Pipeline 执行，P50/P95 断言）。

---

## 隐私声明

- **不持久化**原始音频，处理完成后立即删除临时文件
- **不上传**可识别个人信息
- 日志**不记录**完整语音转写文本
- 默认使用**设备端**语音识别（`requiresOnDeviceRecognition = true`）
- Bundle ID：`ai.holoo.voxlite`

---

## 文档索引

| 文档 | 路径 | 说明 |
|---|---|---|
| 需求与技术方案 | [`docs/需求与技术方案规格说明.md`](docs/需求与技术方案规格说明.md) | PRD + TSD 完整规格 |
| 开发执行计划 | [`docs/VoxLite_开发执行计划_WBS.md`](docs/VoxLite_开发执行计划_WBS.md) | WBS 工作包与里程碑 |
| 测试清单 | [`docs/VoxLite_测试清单与验收检查表.md`](docs/VoxLite_测试清单与验收检查表.md) | 功能 / 性能 / 验收检查表 |
| UX/UI 原型 | [`docs/HolooVoxLite_UXUI_Prototype.html`](docs/HolooVoxLite_UXUI_Prototype.html) | 可交互引导与使用态原型 |
| GitFlow 策略 | [`docs/GITFLOW.md`](docs/GITFLOW.md) | 分支模型与合并规则详解 |
| 代码生成规则 | [`.trae/rules/rules.md`](.trae/rules/rules.md) | AI 辅助开发约束规则 |

---

<p align="center">
  <sub>和乐 · Holoo — 让工作生活更和乐美满</sub>
</p>
