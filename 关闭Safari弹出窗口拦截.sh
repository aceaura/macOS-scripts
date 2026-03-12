#!/bin/bash
# 关闭 Safari 的弹出窗口拦截（允许弹出窗口）
# 用法: bash 关闭Safari弹出窗口拦截.sh

set -euo pipefail

defaults write com.apple.Safari WebKitJavaScriptCanOpenWindowsAutomatically -bool true
defaults write com.apple.Safari "com.apple.Safari.ContentPageGroupIdentifier.WebKit2JavaScriptCanOpenWindowsAutomatically" -bool true

echo "✅ 已关闭 Safari 弹出窗口拦截"
echo "⚠️  如果 Safari 正在运行，需要重启 Safari 才能生效"
