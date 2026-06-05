#!/bin/bash
# ============================================================
# MkDocs 知识库一键提交 + 部署脚本
#
# 首次使用（Git Bash 中执行）:
#   cd /d/Work/Dev-KB
#   chmod +x deploy.sh
#
# 日常用法:
#   ./deploy.sh "提交信息"
#
# 示例:
#   ./deploy.sh "docs: 补充部署手册常见问题排查"
# ============================================================

set -e  # 遇到错误立即退出

# 检查是否传入提交信息
if [ $# -eq 0 ]; then
    echo "错误: 请提供 git commit 信息"
    echo "用法: ./deploy.sh \"提交信息\""
    exit 1
fi

COMMIT_MSG="$1"

echo "=========================================="
echo "  MkDocs 知识库部署脚本"
echo "=========================================="
echo ""

# 步骤1: Git 提交源码
echo "[1/3] 提交源码到 main 分支..."
git add .
git commit -m "$COMMIT_MSG"
git push origin main
echo ""

# 步骤2: 部署到 GitHub Pages
echo "[2/3] 编译并部署到 GitHub Pages..."
mkdocs gh-deploy --clean
echo ""

# 步骤3: 完成
echo "[3/3] 部署完成!"
echo "访问地址: https://2020638630.github.io/mkdocs/"
echo "=========================================="
