#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCHEME="${SCHEME:-voxlite}"
PROJECT_PATH="${PROJECT_PATH:-$ROOT_DIR/voxlite.xcodeproj}"
EXPORT_OPTIONS_PLIST="${EXPORT_OPTIONS_PLIST:-$ROOT_DIR/scripts/beta_export_options.plist}"
NOTARY_PROFILE="${NOTARY_PROFILE:-AC_NOTARY}"
BUILD_MODE="${BUILD_MODE:-auto}"

echo "[1/6] 检查 Xcode 工具链"
if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "❌ 未找到 xcodebuild"
  exit 1
fi
xcodebuild -version

echo "[2/6] 检查导出配置"
if [[ ! -f "$EXPORT_OPTIONS_PLIST" ]]; then
  echo "❌ 缺少 $EXPORT_OPTIONS_PLIST"
  exit 1
fi

echo "[3/6] 检查公证凭据"
if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  echo "❌ notary profile 无效：$NOTARY_PROFILE"
  echo "   请执行 xcrun notarytool store-credentials"
  exit 1
fi

if [[ "$BUILD_MODE" == "auto" ]]; then
  if [[ -d "$PROJECT_PATH" ]]; then
    BUILD_MODE="project"
  else
    BUILD_MODE="package"
  fi
fi

echo "[4/6] 检查构建模式：$BUILD_MODE"
if [[ "$BUILD_MODE" == "project" ]]; then
  [[ -d "$PROJECT_PATH" ]] || { echo "❌ 未找到项目：$PROJECT_PATH"; exit 1; }
  xcodebuild -project "$PROJECT_PATH" -list >/dev/null
else
  [[ -f "$ROOT_DIR/Package.swift" ]] || { echo "❌ 未找到 Package.swift"; exit 1; }
  xcodebuild -list >/dev/null
fi

echo "[5/6] 检查 Scheme：$SCHEME"
if [[ "$BUILD_MODE" == "project" ]]; then
  xcodebuild -project "$PROJECT_PATH" -scheme "$SCHEME" -showBuildSettings >/dev/null
else
  xcodebuild -scheme "$SCHEME" -showBuildSettings >/dev/null
fi

echo "[6/6] 自检代码质量"
swift build --disable-sandbox >/dev/null
swift run --disable-sandbox VoxLiteSelfCheck >/dev/null

echo "✅ Beta 预检通过"
