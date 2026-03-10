#!/bin/bash
# 在 macOS 系统偏好设置中，针对 Karabiner VirtualHIDKeyboard 交换 Command ↔ Control
# 等同于：系统设置 → 键盘 → 修饰键 → 选择 Karabiner 设备 → 交换
# 自动检测 Karabiner 虚拟键盘的 vendor/product ID
# 用法: bash 交换Command和Control键.sh

set -euo pipefail

# 自动检测 Karabiner VirtualHIDKeyboard 的 vendor 和 product ID
DEVICE_INFO=$(hidutil list 2>/dev/null | grep -i "Karabiner.*VirtualHIDKeyboard" | head -1)

if [ -z "$DEVICE_INFO" ]; then
    echo "❌ 未检测到 Karabiner VirtualHIDKeyboard，请确认 Karabiner-Elements 已安装并运行"
    exit 1
fi

# hidutil list 输出格式: VendorID ProductID ...
VENDOR_HEX=$(echo "$DEVICE_INFO" | awk '{print $1}')
PRODUCT_HEX=$(echo "$DEVICE_INFO" | awk '{print $2}')

# 转为十进制
VENDOR_DEC=$((VENDOR_HEX))
PRODUCT_DEC=$((PRODUCT_HEX))

DEVICE_KEY="com.apple.keyboard.modifiermapping.${VENDOR_DEC}-${PRODUCT_DEC}-0"

echo "🔍 检测到 Karabiner VirtualHIDKeyboard"
echo "   Vendor ID:  ${VENDOR_HEX} (${VENDOR_DEC})"
echo "   Product ID: ${PRODUCT_HEX} (${PRODUCT_DEC})"
echo "   设备键:     ${DEVICE_KEY}"

# 键码（十进制）:
# 30064771296 = 0x7000000E0 = Left Control
# 30064771299 = 0x7000000E3 = Left Command
# 30064771300 = 0x7000000E4 = Right Control
# 30064771303 = 0x7000000E7 = Right Command

defaults -currentHost write -g "$DEVICE_KEY" -array \
    '<dict><key>HIDKeyboardModifierMappingSrc</key><integer>30064771303</integer><key>HIDKeyboardModifierMappingDst</key><integer>30064771300</integer></dict>' \
    '<dict><key>HIDKeyboardModifierMappingSrc</key><integer>30064771296</integer><key>HIDKeyboardModifierMappingDst</key><integer>30064771299</integer></dict>' \
    '<dict><key>HIDKeyboardModifierMappingSrc</key><integer>30064771300</integer><key>HIDKeyboardModifierMappingDst</key><integer>30064771303</integer></dict>' \
    '<dict><key>HIDKeyboardModifierMappingSrc</key><integer>30064771299</integer><key>HIDKeyboardModifierMappingDst</key><integer>30064771296</integer></dict>'

echo "✅ 已交换 Karabiner VirtualHIDKeyboard 的 Command ↔ Control 键"
echo "⚠️  可能需要注销并重新登录才能完全生效"
