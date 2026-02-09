#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# 禁止Mac自动休眠.sh
# 管理 macOS 自动休眠相关设置（系统休眠、硬盘休眠、Power Nap 等）
# ============================================================

is_root() {
  [[ "${EUID:-$(id -u)}" -eq 0 ]]
}

need_root_msg() {
  echo "错误：此操作需要 root 权限。请使用 sudo 重新运行：sudo $0" >&2
}

usage() {
  cat <<'EOF'
用法:
  sudo ./禁止Mac自动休眠.sh [选项]

选项:
  --interactive             显示交互菜单（默认：不带参数时进入交互）。
  --status                  仅显示当前状态，不做任何修改。
  --disable-sleep           禁止自动休眠（系统休眠、硬盘休眠、Power Nap 等）。
  --restore-sleep           还原自动休眠设置。
  -h, --help                显示本帮助。

默认行为（不带参数）:
  进入交互菜单。

注意:
  禁止自动休眠会增加电量消耗，笔记本用户请注意电池续航。
EOF
}

get_pmset_value() {
  local key="$1"
  local default_val="$2"
  local val
  val="$(pmset -g custom 2>/dev/null | awk -v k="$key" '$1 == k {print $2; exit}')"
  if [[ -z "$val" ]]; then
    echo "$default_val"
  else
    echo "$val"
  fi
}

format_minutes() {
  local val="$1"
  local label="$2"
  if [[ "$val" == "0" ]]; then
    echo "永不（已禁止）"
  else
    echo "${val} 分钟"
  fi
}

get_hibernatemode() {
  local val
  val="$(get_pmset_value hibernatemode "未知")"
  case "$val" in
    0) echo "0（不休眠到磁盘）" ;;
    3) echo "3（默认：内存+磁盘）" ;;
    25) echo "25（仅磁盘休眠）" ;;
    *) echo "$val" ;;
  esac
}

get_powernap() {
  local val
  val="$(get_pmset_value powernap "未知")"
  case "$val" in
    0) echo "关" ;;
    1) echo "开" ;;
    *) echo "$val" ;;
  esac
}

get_autopoweroff() {
  local val
  val="$(get_pmset_value autopoweroff "未知")"
  case "$val" in
    0) echo "关" ;;
    1) echo "开" ;;
    *) echo "$val" ;;
  esac
}

get_standby() {
  local val
  val="$(get_pmset_value standby "未知")"
  case "$val" in
    0) echo "关" ;;
    1) echo "开" ;;
    *) echo "$val" ;;
  esac
}

print_status() {
  local sleep_val disksleep_val

  sleep_val="$(get_pmset_value sleep "未知")"
  disksleep_val="$(get_pmset_value disksleep "未知")"

  echo "当前状态:"
  echo "  系统休眠时间:            $(format_minutes "$sleep_val" "系统休眠")"
  echo "  硬盘休眠时间:            $(format_minutes "$disksleep_val" "硬盘休眠")"
  echo "  休眠模式 (hibernatemode): $(get_hibernatemode)"
  echo "  Power Nap:               $(get_powernap)"
  echo "  自动断电 (autopoweroff):  $(get_autopoweroff)"
  echo "  待机模式 (standby):       $(get_standby)"
}

disable_auto_sleep() {
  is_root || { need_root_msg; return 2; }

  echo "正在禁止自动休眠..."

  # 禁止系统自动休眠（0 = 永不）
  pmset -a sleep 0 2>/dev/null || true

  # 禁止硬盘自动休眠
  pmset -a disksleep 0 2>/dev/null || true

  # 设置休眠模式为 0（不写入磁盘）
  pmset -a hibernatemode 0 2>/dev/null || true

  # 关闭 Power Nap
  pmset -a powernap 0 2>/dev/null || true

  # 关闭自动断电
  pmset -a autopoweroff 0 2>/dev/null || true

  # 关闭待机模式
  pmset -a standby 0 2>/dev/null || true

  # 使用 caffeinate 提示（不阻塞，仅提示用户）
  echo ""
  echo "已禁止自动休眠（尽力而为）。"
  echo "提示：如需临时阻止休眠，也可在终端运行 caffeinate 命令。"
  echo "设置已立即生效。"
}

restore_auto_sleep() {
  is_root || { need_root_msg; return 2; }

  echo "正在还原自动休眠设置..."

  # 还原系统休眠时间（默认 10 分钟，台式机通常更长）
  pmset -a sleep 10 2>/dev/null || true

  # 还原硬盘休眠时间（默认 10 分钟）
  pmset -a disksleep 10 2>/dev/null || true

  # 还原休眠模式（默认 3 = 内存+磁盘）
  pmset -a hibernatemode 3 2>/dev/null || true

  # 开启 Power Nap
  pmset -a powernap 1 2>/dev/null || true

  # 开启自动断电
  pmset -a autopoweroff 1 2>/dev/null || true

  # 开启待机模式
  pmset -a standby 1 2>/dev/null || true

  echo "已还原自动休眠设置（尽力而为）。"
  echo "设置已立即生效。"
}

interactive_menu() {
  while true; do
    echo ""
    print_status
    echo ""
    echo "请选择操作："
    echo "  1) 禁止自动休眠"
    echo "  2) 还原自动休眠"
    echo "  3) 显示当前状态"
    echo "  0) 退出"
    printf "> "
    read -r choice
    case "$choice" in
      1)
        disable_auto_sleep || true
        ;;
      2)
        restore_auto_sleep || true
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
DISABLE_SLEEP=0
RESTORE_SLEEP=0

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
      --disable-sleep)
        DISABLE_SLEEP=1
        ;;
      --restore-sleep)
        RESTORE_SLEEP=1
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

if [[ "$DISABLE_SLEEP" -eq 1 && "$RESTORE_SLEEP" -eq 1 ]]; then
  echo "错误：不能同时使用 --disable-sleep 与 --restore-sleep。" >&2
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

if [[ "$DISABLE_SLEEP" -eq 1 ]]; then
  disable_auto_sleep
  did_anything=1
fi

if [[ "$RESTORE_SLEEP" -eq 1 ]]; then
  restore_auto_sleep
  did_anything=1
fi

if [[ "$did_anything" -eq 0 ]]; then
  usage >&2
  exit 2
fi
