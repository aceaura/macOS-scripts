#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# 禁止Mac自动锁屏.sh
# 管理 macOS 自动锁屏相关设置（屏幕保护程序启动时间、锁屏延迟等）
# ============================================================

read_defaults_value() {
  local domain="$1"
  local key="$2"
  local default_val="$3"
  local value
  if ! value="$(defaults read "$domain" "$key" 2>/dev/null)"; then
    echo "$default_val"
    return 0
  fi
  if [[ -z "$value" ]]; then
    echo "$default_val"
    return 0
  fi
  echo "$value"
}

is_root() {
  [[ "${EUID:-$(id -u)}" -eq 0 ]]
}

need_root_msg() {
  echo "错误：此操作需要 root 权限。请使用 sudo 重新运行：sudo $0" >&2
}

usage() {
  cat <<'EOF'
用法:
  sudo ./禁止Mac自动锁屏.sh [选项]

选项:
  --interactive             显示交互菜单（默认：不带参数时进入交互）。
  --status                  仅显示当前状态，不做任何修改。
  --disable-lock            禁止自动锁屏（关闭屏幕保护程序、关闭锁屏要求）。
  --restore-lock            还原自动锁屏设置。
  -h, --help                显示本帮助。

默认行为（不带参数）:
  进入交互菜单。

注意:
  禁止自动锁屏会降低安全性，请在安全的环境中使用。
EOF
}

get_screensaver_idle_time() {
  local val
  val="$(read_defaults_value com.apple.screensaver idleTime "未设置")"
  if [[ "$val" == "0" ]]; then
    echo "永不（已禁止）"
  elif [[ "$val" == "未设置" ]]; then
    echo "未设置（使用系统默认）"
  else
    echo "${val} 秒"
  fi
}

get_screen_lock_enabled() {
  # askForPassword: 1=需要密码, 0=不需要
  local val
  val="$(read_defaults_value com.apple.screensaver askForPassword "未设置")"
  case "$val" in
    1) echo "开（需要密码）" ;;
    0) echo "关（不需要密码）" ;;
    *) echo "未设置（使用系统默认）" ;;
  esac
}

get_screen_lock_delay() {
  # askForPasswordDelay: 锁屏前的延迟秒数
  local val
  val="$(read_defaults_value com.apple.screensaver askForPasswordDelay "未设置")"
  if [[ "$val" == "0" ]]; then
    echo "立即"
  elif [[ "$val" == "未设置" ]]; then
    echo "未设置（使用系统默认）"
  else
    echo "${val} 秒"
  fi
}

get_display_sleep_time() {
  local val
  val="$(pmset -g custom 2>/dev/null | awk '/displaysleep/ {print $2; exit}')"
  if [[ -z "$val" ]]; then
    echo "未知"
  elif [[ "$val" == "0" ]]; then
    echo "永不"
  else
    echo "${val} 分钟"
  fi
}

print_status() {
  echo "当前状态:"
  echo "  屏幕保护程序启动时间:    $(get_screensaver_idle_time)"
  echo "  唤醒后需要密码:          $(get_screen_lock_enabled)"
  echo "  密码要求延迟:            $(get_screen_lock_delay)"
  echo "  显示器休眠时间:          $(get_display_sleep_time)"
}

disable_auto_lock() {
  is_root || { need_root_msg; return 2; }

  echo "正在禁止自动锁屏..."

  # 关闭屏幕保护程序（设置空闲时间为 0 = 永不启动）
  defaults write com.apple.screensaver idleTime -int 0 2>/dev/null || true

  # 关闭唤醒后需要密码
  defaults write com.apple.screensaver askForPassword -int 0 2>/dev/null || true

  # 设置密码延迟为最大值（即使被重新开启也有缓冲）
  defaults write com.apple.screensaver askForPasswordDelay -int 2147483647 2>/dev/null || true

  # 设置显示器不自动关闭（当前电源模式）
  pmset -a displaysleep 0 2>/dev/null || true

  echo "已禁止自动锁屏（尽力而为）。"
  echo "可能需要注销或重启后才能完全生效。"
}

restore_auto_lock() {
  is_root || { need_root_msg; return 2; }

  echo "正在还原自动锁屏设置..."

  # 还原屏幕保护程序空闲时间（默认 300 秒 = 5 分钟）
  defaults write com.apple.screensaver idleTime -int 300 2>/dev/null || true

  # 开启唤醒后需要密码
  defaults write com.apple.screensaver askForPassword -int 1 2>/dev/null || true

  # 设置密码延迟为立即（0 秒）
  defaults write com.apple.screensaver askForPasswordDelay -int 0 2>/dev/null || true

  # 还原显示器休眠时间（默认 10 分钟）
  pmset -a displaysleep 10 2>/dev/null || true

  echo "已还原自动锁屏设置（尽力而为）。"
  echo "可能需要注销或重启后才能完全生效。"
}

interactive_menu() {
  while true; do
    echo ""
    print_status
    echo ""
    echo "请选择操作："
    echo "  1) 禁止自动锁屏"
    echo "  2) 还原自动锁屏"
    echo "  3) 显示当前状态"
    echo "  0) 退出"
    printf "> "
    read -r choice
    case "$choice" in
      1)
        disable_auto_lock || true
        ;;
      2)
        restore_auto_lock || true
        ;;
      3)
        echo ""
        print_status
        ;;
      0)
        exit 0
        ;;
      *)
        echo "无效选择：$choice" >&2
        ;;
    esac
  done
}

# ---- 参数解析 ----
INTERACTIVE=0
STATUS_ONLY=0
DISABLE_LOCK=0
RESTORE_LOCK=0

if [[ "$#" -eq 0 ]]; then
  INTERACTIVE=1
else
  for arg in "$@"; do
    case "$arg" in
      --interactive)
        INTERACTIVE=1
        ;;
      --status)
        STATUS_ONLY=1
        ;;
      --disable-lock)
        DISABLE_LOCK=1
        ;;
      --restore-lock)
        RESTORE_LOCK=1
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "未知选项：$arg" >&2
        usage >&2
        exit 2
        ;;
    esac
  done
fi

if [[ "$DISABLE_LOCK" -eq 1 && "$RESTORE_LOCK" -eq 1 ]]; then
  echo "错误：不能同时使用 --disable-lock 与 --restore-lock。" >&2
  exit 2
fi

if [[ "$INTERACTIVE" -eq 1 ]]; then
  interactive_menu
fi

if [[ "$STATUS_ONLY" -eq 1 ]]; then
  print_status
  exit 0
fi

did_anything=0

if [[ "$DISABLE_LOCK" -eq 1 ]]; then
  disable_auto_lock
  did_anything=1
fi

if [[ "$RESTORE_LOCK" -eq 1 ]]; then
  restore_auto_lock
  did_anything=1
fi

if [[ "$did_anything" -eq 0 ]]; then
  usage >&2
  exit 2
fi
