#!/bin/bash
# 开启 Safari 开发菜单（Web Inspector / F12 调试功能）
# 用法: bash 开启Safari开发者模式.sh

set -euo pipefail

defaults write com.apple.Safari IncludeDevelopMenu -bool true
defaults write com.apple.Safari WebKitDeveloperExtrasEnabledPreferenceKey -bool true
defaults write com.apple.Safari "com.apple.Safari.ContentPageGroupIdentifier.WebKit2DeveloperExtrasEnabled" -bool true

echo "✅ 已开启 Safari 开发者菜单"
echo "⚠️  如果 Safari 正在运行，需要重启 Safari 才能生效"
