# VoxLite GitFlow 分支策略

## 分支模型总览

```
main          ──────●──────────────────────────────●──── (仅接受 release/* 与 hotfix/* 合入)
                    │                              │
release/1.0   ──────┤       ●──────────────────●──┘
                    │       │                  │
develop       ──●───●───●───●──●───────────────●──── (日常集成主线)
                │       │       │
feature/*    ──●─●─┘   ●─●─┘  ●─●─┘           (功能分支，从 develop 拉取)

hotfix/*      ──────────────────────────●──●──┘       (从 main 拉取，合回 main + develop)
```

## 分支命名规范

| 分支类型 | 命名格式 | 示例 |
|---|---|---|
| 主线 | `main` | `main` |
| 集成线 | `develop` | `develop` |
| 功能分支 | `feature/<票号>-<简短描述>` | `feature/VOX-42-hotkey-custom` |
| 发布分支 | `release/<版本号>` | `release/1.0.0` |
| 热修复分支 | `hotfix/<票号>-<简短描述>` | `hotfix/VOX-99-injection-crash` |

## 各分支生命周期

### main
- **只读**：禁止直接推送，只接受 PR 合入。
- **合入来源**：`release/*` 和 `hotfix/*`。
- **每次合入必须打 tag**（语义化版本）。
- **触发**：自动公证打包流程（`beta_archive_and_notarize.sh`）。

### develop
- **集成主线**：所有 `feature/*` 向此合入。
- **允许直接推送**：仅限 `chore`、`docs` 类小改动；功能变更必须走 PR。
- **合入要求**：CI 自检通过（`SELF_CHECK_OK`）。

### feature/*
- **从 develop 拉取**，合回 develop。
- **生命周期**：完成并合入后立即删除。
- **PR 合入前必须**：rebase 到最新 develop、自检通过、至少 1 人 Review。

### release/*
- **从 develop 拉取**，合回 main **和** develop。
- **只允许**：版本号更新、文案修正、最后关头 bugfix。
- **禁止**：新功能。
- **合入 main 前**：必须通过性能门禁（P50 < 1000ms，P95 < 1800ms）。

### hotfix/*
- **从 main 拉取**，合回 main **和** develop。
- **适用场景**：线上 P0 缺陷、文本丢失、崩溃。
- **必须附带**：可复现的回归测试。

## PR 准入规则

所有合入 `main` 和 `develop` 的 PR 必须满足：

1. **自检通过**：终端输出 `SELF_CHECK_OK`
2. **Reviewer 数量**：≥ 1 人（合入 main 需 ≥ 2 人）
3. **无强制推送**：禁止 `--force` 到受保护分支
4. **线性历史**：squash merge 或 rebase merge，禁止 merge commit 直推 main
5. **Commit 规范**：遵循 Conventional Commits（见下）

## Commit Message 规范

格式：`<type>(<scope>): <描述>`

| type | 适用场景 |
|---|---|
| `feat` | 新功能 |
| `fix` | 缺陷修复（必须先有回归测试） |
| `test` | 新增或修改测试 |
| `refactor` | 重构（不改变行为） |
| `perf` | 性能优化 |
| `chore` | 构建/工具链/依赖 |
| `docs` | 文档 |
| `ci` | CI/CD 配置 |

scope 示例：`input`、`core`、`output`、`system`、`feature`、`pipeline`

示例：
```
feat(input): support custom hotkey configuration
fix(output): restore clipboard after injection failure
test(pipeline): add regression for timeout retry exhaustion
```

## Tag 规范

合入 main 后立即打 tag：

```
v<MAJOR>.<MINOR>.<PATCH>[-<pre>]

示例：v1.0.0 / v1.0.1-beta.1 / v1.1.0-rc.1
```

## 紧急回滚流程

若 main 合入后发现 P0 问题：

1. **不要 revert**（会破坏历史）→ 立即拉 `hotfix/*` 分支
2. 在 hotfix 分支先补回归测试，再提交修复
3. 走正常 hotfix PR 流程，合入 main + develop
4. 若需要紧急下线，使用 `git tag v<version>-revoked` 标记问题版本
