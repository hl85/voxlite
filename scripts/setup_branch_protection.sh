#!/usr/bin/env bash
# scripts/setup_branch_protection.sh
# 通过 GitHub CLI 一键配置分支保护规则
# 前置：brew install gh && gh auth login
# 执行：REPO=hl85/voxlite bash scripts/setup_branch_protection.sh

set -euo pipefail

REPO="${REPO:-hl85/voxlite}"

echo "📋 配置分支保护规则：$REPO"
echo ""

echo "[1/2] 配置 main 分支保护..."
gh api \
  --method PUT \
  -H "Accept: application/vnd.github+json" \
  "/repos/$REPO/branches/main/protection" \
  --input - <<'EOF'
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["Build & Self Check", "Lint Commit Messages", "Branch Policy Guard"]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "required_approving_review_count": 2,
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": false,
    "require_last_push_approval": true
  },
  "restrictions": null,
  "required_linear_history": true,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_conversation_resolution": true
}
EOF
echo "   ✅ main 分支保护已配置"
echo ""

echo "[2/2] 配置 develop 分支保护..."
gh api \
  --method PUT \
  -H "Accept: application/vnd.github+json" \
  "/repos/$REPO/branches/develop/protection" \
  --input - <<'EOF'
{
  "required_status_checks": {
    "strict": false,
    "contexts": ["Build & Self Check"]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": {
    "required_approving_review_count": 1,
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": false,
    "require_last_push_approval": false
  },
  "restrictions": null,
  "required_linear_history": false,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_conversation_resolution": false
}
EOF
echo "   ✅ develop 分支保护已配置"
echo ""
echo "🎉 完成！main 需要 2 人 Review + CI 全通过；develop 需要 1 人 Review + 自检通过。"
