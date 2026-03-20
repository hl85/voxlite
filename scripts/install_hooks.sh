#!/usr/bin/env bash
# scripts/install_hooks.sh
# 一键安装本地 Git Hooks
# 执行：bash scripts/install_hooks.sh

set -euo pipefail

HOOKS_DIR=".githooks"
HOOK_FILES=("commit-msg" "pre-commit" "pre-push")

echo "🔧 安装 VoxLite Git Hooks..."
echo ""

for HOOK in "${HOOK_FILES[@]}"; do
    HOOK_PATH="$HOOKS_DIR/$HOOK"
    if [[ -f "$HOOK_PATH" ]]; then
        chmod +x "$HOOK_PATH"
        echo "   ✅ $HOOK → 已设置可执行权限"
    else
        echo "   ⚠️  $HOOK → 文件不存在，跳过"
    fi
done

echo ""
git config core.hooksPath "$HOOKS_DIR"
echo "✅ git hooks 路径已设置为：$HOOKS_DIR"
echo ""
echo "已安装的 Hooks："
echo "  commit-msg  → 校验 Conventional Commits 格式"
echo "  pre-commit  → 拦截直接向 main 提交"
echo "  pre-push    → 推送前执行 Build + VoxLiteSelfCheck"
echo ""
echo "如需卸载：git config --unset core.hooksPath"
