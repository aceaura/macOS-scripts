#!/bin/bash
# 将 F1-F12 设为标准功能键（而非媒体键）
# 按住 fn 才触发媒体功能（亮度、音量等）
# 用法: bash 启用标准功能键.sh

set -euo pipefail

defaults write -g com.apple.keyboard.fnState -bool true

echo "✅ 已将 F1-F12 设为标准功能键"
echo "⚠️  可能需要注销并重新登录才能生效"
