#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="${PROJECT_PATH:-$ROOT_DIR/voxlite.xcodeproj}"
SCHEME="${SCHEME:-voxlite}"
CONFIGURATION="${CONFIGURATION:-Release}"
ARCHIVE_PATH="${ARCHIVE_PATH:-$ROOT_DIR/build/VoxLiteApp.xcarchive}"
EXPORT_PATH="${EXPORT_PATH:-$ROOT_DIR/build/export}"
EXPORT_OPTIONS_PLIST="${EXPORT_OPTIONS_PLIST:-$ROOT_DIR/scripts/beta_export_options.plist}"
BUNDLE_ID="${BUNDLE_ID:-ai.holoo.voxlite}"
NOTARY_PROFILE="${NOTARY_PROFILE:-AC_NOTARY}"
BUILD_MODE="${BUILD_MODE:-auto}"

mkdir -p "$ROOT_DIR/build"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "缺少 xcodebuild，请安装 Xcode。"
  exit 1
fi

if ! xcodebuild -version >/dev/null 2>&1; then
  echo "当前 developer directory 无法使用 xcodebuild，请执行："
  echo "sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
  exit 1
fi

if [[ ! -f "$EXPORT_OPTIONS_PLIST" ]]; then
  echo "未找到导出配置：$EXPORT_OPTIONS_PLIST"
  echo "请先从模板复制：scripts/beta_export_options.plist.template"
  exit 1
fi

if [[ "$BUILD_MODE" == "auto" ]]; then
  if [[ -d "$PROJECT_PATH" ]]; then
    BUILD_MODE="project"
  else
    BUILD_MODE="package"
  fi
fi

if [[ "$BUILD_MODE" == "project" ]]; then
  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "platform=macOS" \
    archive \
    -archivePath "$ARCHIVE_PATH"
else
  xcodebuild \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "platform=macOS" \
    archive \
    -archivePath "$ARCHIVE_PATH"
fi

xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS_PLIST"

APP_PATH="$(find "$EXPORT_PATH" -name "*.app" -maxdepth 2 | head -n 1)"
if [[ -z "${APP_PATH:-}" ]]; then
  echo "导出失败：未找到 .app"
  exit 1
fi

ZIP_PATH="$EXPORT_PATH/${BUNDLE_ID}.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP_PATH"

echo "Beta 包已完成归档、公证与装订：$APP_PATH"
