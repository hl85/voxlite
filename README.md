# VoxLite 冲刺开发说明

## 当前状态

- 已完成主链路：按住 Fn 录音 → 松开处理 → 文本注入。
- 已完成 M2 关键能力：权限引导、错误可恢复、超时重试、仅转录降级。
- 已完成高优先回归：状态机、路由、权限映射、重试/超时、Fn 边界、注入回退、App 状态机。
- 已接入性能门槛断言：P50 < 1000ms，P95 < 1800ms。

## 运行与自检

- 构建：`swift build --disable-sandbox`
- 自检：`swift run --disable-sandbox VoxLiteSelfCheck`
- 自检通过标志：终端输出 `SELF_CHECK_OK`

## Beta 打包脚本

- 导出配置模板：`scripts/beta_export_options.plist.template`
- 预检脚本：`scripts/beta_preflight_check.sh`
- 归档公证脚本：`scripts/beta_archive_and_notarize.sh`

执行前需准备：

- 可用 Xcode 工具链（非 Command Line Tools）
- 构建模式：
  - `BUILD_MODE=project`：使用 `voxlite.xcodeproj`
  - `BUILD_MODE=package`：直接按 Package Scheme 归档
  - 默认 `auto`：有工程走 project，否则走 package
- `scripts/beta_export_options.plist`（由模板复制并填写 Team ID）
- `xcrun notarytool store-credentials` 生成的 keychain profile（默认 `AC_NOTARY`）

执行示例：

```bash
cp scripts/beta_export_options.plist.template scripts/beta_export_options.plist
chmod +x scripts/beta_preflight_check.sh scripts/beta_archive_and_notarize.sh
scripts/beta_preflight_check.sh
BUILD_MODE=package scripts/beta_archive_and_notarize.sh
```

## 目录说明

- `Sources/VoxLiteInput`：输入监听与录音采集
- `Sources/VoxLiteCore`：转写、上下文、清洗、编排
- `Sources/VoxLiteOutput`：注入与回退
- `Sources/VoxLiteSystem`：权限、日志、指标、性能采样
- `Sources/VoxLiteFeature`：App 状态机与交互状态
- `Sources/VoxLiteApp`：菜单栏界面入口
- `Sources/VoxLiteSelfCheck`：统一自检链路
