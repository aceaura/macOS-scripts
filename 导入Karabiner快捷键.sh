#!/bin/bash
# 一键删除旧快捷键并从 Karabiner/ 目录导入新快捷键
# 用法: bash 导入Karabiner快捷键.sh

set -euo pipefail

KARABINER_CONFIG="$HOME/.config/karabiner/karabiner.json"
RULES_DIR="$(dirname "$0")/Karabiner"

# 检查配置文件是否存在
if [ ! -f "$KARABINER_CONFIG" ]; then
    echo "❌ 未找到 Karabiner 配置文件: $KARABINER_CONFIG"
    exit 1
fi

# 检查规则目录是否存在
if [ ! -d "$RULES_DIR" ]; then
    echo "❌ 未找到规则目录: $RULES_DIR"
    exit 1
fi

# 检查 jq 是否安装
if ! command -v jq &> /dev/null; then
    echo "❌ 需要安装 jq，请运行: brew install jq"
    exit 1
fi

# 收集所有 JSON 规则文件（排除 .DS_Store 等）
RULE_FILES=("$RULES_DIR"/*.json)
if [ ${#RULE_FILES[@]} -eq 0 ]; then
    echo "❌ 规则目录中没有找到 JSON 文件"
    exit 1
fi

echo "📂 找到 ${#RULE_FILES[@]} 个规则文件:"
for f in "${RULE_FILES[@]}"; do
    echo "   - $(basename "$f")"
done

# 合并所有规则文件为一个 JSON 数组
MERGED_RULES=$(jq -s '.' "${RULE_FILES[@]}")

# 删除旧的 complex_modifications rules 并写入新规则
# 保留 profiles 中的其他设置（name, selected, virtual_hid_keyboard 等）
jq --argjson rules "$MERGED_RULES" '
    .profiles[0].complex_modifications.rules = $rules |
    .profiles[0].simple_modifications = []
' "$KARABINER_CONFIG" > "${KARABINER_CONFIG}.tmp"
mv "${KARABINER_CONFIG}.tmp" "$KARABINER_CONFIG"

echo "✅ 已清除旧快捷键并导入新规则"
echo ""

# 显示导入的规则摘要
echo "📋 导入的规则:"
echo "$MERGED_RULES" | jq -r '.[] | "   - \(.description) (\(.manipulators | length) 个快捷键)"'

TOTAL=$(echo "$MERGED_RULES" | jq '[.[].manipulators | length] | add')
echo ""
echo "🎉 共导入 $TOTAL 个快捷键映射，Karabiner 会自动加载新配置"
