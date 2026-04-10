#!/bin/bash
# 管理 LocalStack 开机自启动（通过 LaunchAgent）
# 用法: bash 开机启动LocalStack.sh [on|off|status]
# 不带参数时交互式选择

set -euo pipefail

PLIST_NAME="com.user.localstack"
PLIST_PATH="$HOME/Library/LaunchAgents/${PLIST_NAME}.plist"
LOCALSTACK_BIN=$(which localstack 2>/dev/null || echo "")
DOCKER_BIN=$(which docker 2>/dev/null || echo "")

if [ -z "$LOCALSTACK_BIN" ]; then
    echo "❌ 未找到 localstack，请先安装"
    exit 1
fi

if [ -z "$DOCKER_BIN" ]; then
    echo "❌ 未找到 docker，请先安装"
    exit 1
fi

get_status() {
    if [ -f "$PLIST_PATH" ]; then
        echo "on"
    else
        echo "off"
    fi
}

enable_autostart() {
    # 创建启动包装脚本，等待 Docker 就绪后再启动 LocalStack
    WRAPPER="$HOME/.local/bin/localstack-start.sh"
    mkdir -p "$(dirname "$WRAPPER")"
    cat > "$WRAPPER" << 'SCRIPT'
#!/bin/bash
MAX_WAIT=300
WAITED=0
while ! docker info > /dev/null 2>&1; do
    if [ "$WAITED" -ge "$MAX_WAIT" ]; then
        echo "$(date): Docker 未能在 ${MAX_WAIT} 秒内启动，放弃" >&2
        exit 1
    fi
    sleep 5
    WAITED=$((WAITED + 5))
done
echo "$(date): Docker 已就绪，等待了 ${WAITED} 秒"
localstack start -d
SCRIPT
    chmod +x "$WRAPPER"

    cat > "$PLIST_PATH" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${PLIST_NAME}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${WRAPPER}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${HOME}/Library/Logs/localstack.log</string>
    <key>StandardErrorPath</key>
    <string>${HOME}/Library/Logs/localstack.error.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>
</dict>
</plist>
EOF
    echo "✅ 已开启 LocalStack 开机自启动"
}

disable_autostart() {
    if [ -f "$PLIST_PATH" ]; then
        launchctl unload "$PLIST_PATH" 2>/dev/null || true
        rm -f "$PLIST_PATH"
        echo "✅ 已关闭 LocalStack 开机自启动"
    else
        echo "ℹ️  LocalStack 开机自启动本来就是关闭的"
    fi
}

ACTION="${1:-}"

if [ -z "$ACTION" ]; then
    CURRENT=$(get_status)
    echo "📋 LocalStack 开机自启动当前状态: $CURRENT"
    echo ""
    echo "  1) 开启"
    echo "  2) 关闭"
    echo ""
    read -rp "请选择 [1/2]: " CHOICE
    case "$CHOICE" in
        1) ACTION="on" ;;
        2) ACTION="off" ;;
        *) echo "❌ 无效选择"; exit 1 ;;
    esac
fi

case "$ACTION" in
    on|enable)
        enable_autostart
        # 如果当前没有运行 LocalStack，询问是否立即启动
        if ! docker ps 2>/dev/null | grep -q localstack; then
            echo ""
            read -rp "⚡ LocalStack 当前未运行，是否立即启动？[y/N]: " START_NOW
            if [[ "$START_NOW" =~ ^[Yy]$ ]]; then
                localstack start -d
                echo "✅ LocalStack 已启动"
            fi
        fi
        ;;
    off|disable) disable_autostart ;;
    status)     echo "📋 LocalStack 开机自启动当前状态: $(get_status)" ;;
    *)          echo "用法: $0 [on|off|status]"; exit 1 ;;
esac
