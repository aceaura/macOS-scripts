#!/usr/bin/env bash
set -euo pipefail

read_defaults_onoff() {
  # 参数：domain key default_when_unset(开|关)
  local domain="$1"
  local key="$2"
  local default_unset="$3"

  local value
  if ! value="$(defaults read "$domain" "$key" 2>/dev/null)"; then
    value=""
  fi
  if [[ -z "$value" ]]; then
    echo "$default_unset"
    return 0
  fi

  local value_upper
  value_upper="$(printf '%s' "$value" | tr '[:lower:]' '[:upper:]')"
  case "$value_upper" in
    1|TRUE|YES)
      echo "开"
      ;;
    0|FALSE|NO)
      echo "关"
      ;;
    *)
      echo "$default_unset"
      ;;
  esac
}

# 读取抑制状态：系统功能关闭 = 抑制开启
# 使用 plutil 直接读取 plist 文件，绕过 cfprefsd 缓存
read_defaults_suppressed() {
  # 参数：domain key default_when_unset(开|关)
  local domain="$1"
  local key="$2"
  local default_unset="$3"

  local plist_file="${domain}.plist"
  local value

  # 尝试用 plutil 直接读取 plist 文件
  if [[ -f "$plist_file" ]]; then
    value="$(plutil -extract "$key" raw "$plist_file" 2>/dev/null || true)"
  else
    # 回退到 defaults read
    value="$(defaults read "$domain" "$key" 2>/dev/null || true)"
  fi

  if [[ -z "$value" ]]; then
    echo "$default_unset"
    return 0
  fi

  local value_upper
  value_upper="$(printf '%s' "$value" | tr '[:lower:]' '[:upper:]')"
  case "$value_upper" in
    1|TRUE|YES)
      echo "关"  # 系统功能开启 = 抑制关闭
      ;;
    0|FALSE|NO)
      echo "开"  # 系统功能关闭 = 抑制开启
      ;;
    *)
      echo "$default_unset"
      ;;
  esac
}

read_defaults_key_present_onoff() {
  # 参数：domain key
  # 如果 key 存在（即使值为 0）则返回 ON，否则返回 OFF。
  local domain="$1"
  local key="$2"
  if defaults read "$domain" "$key" >/dev/null 2>&1; then
    echo "开"
  else
    echo "关"
  fi
}

softwareupdate_schedule_onoff() {
  local out
  out="$(/usr/sbin/softwareupdate --schedule 2>/dev/null || true)"
  if echo "$out" | grep -Eiq 'turned off|automatic check is off'; then
    echo "开"  # 计划任务关闭 = 抑制开启
  elif echo "$out" | grep -Eiq 'turned on|automatic check is on'; then
    echo "关"  # 计划任务开启 = 抑制关闭
  else
    # 尽力而为：如果无法判断，默认返回"关"，表示抑制未开启。
    echo "关"
  fi
}

HOSTS_FILE="/etc/hosts"
START_MARK="# BEGIN forbid-mac-update.sh apple-block"
END_MARK="# END forbid-mac-update.sh apple-block"
LEGACY_START_MARK="# BEGIN forbit.sh apple-block"
LEGACY_END_MARK="# END forbit.sh apple-block"

is_root() {
  [[ "${EUID:-$(id -u)}" -eq 0 ]]
}

need_root_msg() {
  echo "错误：此操作需要 root 权限。请使用 sudo 重新运行：sudo $0" >&2
}

timestamp() {
  date +%Y%m%d-%H%M%S
}

usage() {
  cat <<'EOF'
用法:
  sudo ./forbid-mac-update.sh [选项]

选项:
  --interactive             显示交互菜单（默认：不带参数时进入交互）。
  --status                  仅显示当前状态，不做任何修改。
  --enable-hosts            应用 Hosts 屏蔽：在 /etc/hosts 中启用屏蔽条目。
  --disable-hosts           还原 Hosts：在 /etc/hosts 中注释屏蔽条目。
  --disable-update-prompts   应用“更新提示抑制”（自动检查/下载/安装关闭；尽力而为）。
  --restore-update-prompts   还原（尽力而为）由 --disable-update-prompts 修改的相关设置。
  -h, --help                 显示本帮助。

默认行为（不带参数）:
  进入交互菜单。

注意:
  应用“提示抑制”可能会隐藏重要安全更新。建议定期手动检查更新。
EOF
}

BLOCK_DOMAINS=(
  "swdist.apple.com"
  "swscan.apple.com"
  "swcdn.apple.com"
  "gdmf.apple.com"
  "mesu.apple.com"
  "xp.apple.com"
)

block_content_enabled() {
  for domain in "${BLOCK_DOMAINS[@]}"; do
    echo "127.0.0.1 $domain"
  done
}

block_content_disabled() {
  for domain in "${BLOCK_DOMAINS[@]}"; do
    echo "# 127.0.0.1 $domain"
  done
}

hosts_block_present() {
  [[ -f "$HOSTS_FILE" ]] || return 1
  grep -Fq "$START_MARK" "$HOSTS_FILE" || grep -Fq "$LEGACY_START_MARK" "$HOSTS_FILE"
}

active_markers() {
  # 返回：NEW | LEGACY | BOTH | NONE
  [[ -f "$HOSTS_FILE" ]] || { echo "NONE"; return 0; }

  local has_new=0 has_legacy=0
  if grep -Fq "$START_MARK" "$HOSTS_FILE"; then
    has_new=1
  fi
  if grep -Fq "$LEGACY_START_MARK" "$HOSTS_FILE"; then
    has_legacy=1
  fi

  if [[ "$has_new" -eq 1 && "$has_legacy" -eq 1 ]]; then
    echo "BOTH"
  elif [[ "$has_new" -eq 1 ]]; then
    echo "NEW"
  elif [[ "$has_legacy" -eq 1 ]]; then
    echo "LEGACY"
  else
    echo "NONE"
  fi
}

extract_hosts_block() {
  # 参数：start_mark end_mark
  local start_mark="$1"
  local end_mark="$2"
  awk -v s="$start_mark" -v e="$end_mark" '
    $0 == s { inside=1; next }
    $0 == e { inside=0 }
    inside==1 { print }
  ' "$HOSTS_FILE"
}

hosts_block_state() {
  # 返回：开 | 关
  if ! hosts_block_present; then
    echo "关"
    return 0
  fi

  local marker_mode block
  marker_mode="$(active_markers)"
  if [[ "$marker_mode" == "NEW" || "$marker_mode" == "BOTH" ]]; then
    block="$(extract_hosts_block "$START_MARK" "$END_MARK")"
  else
    block="$(extract_hosts_block "$LEGACY_START_MARK" "$LEGACY_END_MARK")"
  fi

  local enabled=0 disabled=0
  for domain in "${BLOCK_DOMAINS[@]}"; do
    if echo "$block" | grep -Eq "^[[:space:]]*127\\.0\\.0\\.1[[:space:]]+${domain//./\\.}([[:space:]]+.*)?$"; then
      enabled=$((enabled+1))
    elif echo "$block" | grep -Eq "^[[:space:]]*#[[:space:]]*127\\.0\\.0\\.1[[:space:]]+${domain//./\\.}([[:space:]]+.*)?$"; then
      disabled=$((disabled+1))
    fi
  done
  
  if [[ "$enabled" -gt 0 ]]; then
    echo "开"
  else
    echo "关"
  fi
}

render_hosts_with_block() {
  local out_file="$1"
  local mode="$2" # enabled|disabled（开启/注释屏蔽条目）
  awk -v s1="$START_MARK" -v e1="$END_MARK" -v s2="$LEGACY_START_MARK" -v e2="$LEGACY_END_MARK" '
    BEGIN { skip=0; current_end="" }
    $0 == s1 { skip=1; current_end=e1; next }
    $0 == s2 { skip=1; current_end=e2; next }
    skip == 1 && $0 == current_end { skip=0; current_end=""; next }
    skip == 0 { print }
  ' "$HOSTS_FILE" > "$out_file"

  {
    echo ""
    echo "$START_MARK"
    if [[ "$mode" == "enabled" ]]; then
      block_content_enabled
    else
      block_content_disabled
    fi
    echo "$END_MARK"
  } >> "$out_file"
}

write_hosts_if_changed() {
  local tmp_file="$1"

  if cmp -s "$HOSTS_FILE" "$tmp_file"; then
    return 1
  fi

  cat "$tmp_file" > "$HOSTS_FILE"
  echo "已更新 $HOSTS_FILE"
  return 0
}

enable_hosts_block() {
  [[ -f "$HOSTS_FILE" ]] || { echo "错误：未找到 $HOSTS_FILE" >&2; return 2; }
  is_root || { need_root_msg; return 2; }

  local tmp_file
  tmp_file="$(mktemp /tmp/hosts.XXXXXX)"
  trap 'rm -f "$tmp_file"' RETURN
  render_hosts_with_block "$tmp_file" "enabled"
  if write_hosts_if_changed "$tmp_file"; then
    :
  else
    echo "$HOSTS_FILE 无需修改（Hosts 屏蔽已开启）。"
  fi
}

disable_hosts_block() {
  [[ -f "$HOSTS_FILE" ]] || { echo "错误：未找到 $HOSTS_FILE" >&2; return 2; }
  is_root || { need_root_msg; return 2; }

  local tmp_file
  tmp_file="$(mktemp /tmp/hosts.XXXXXX)"
  trap 'rm -f "$tmp_file"' RETURN
  render_hosts_with_block "$tmp_file" "disabled"
  if write_hosts_if_changed "$tmp_file"; then
    :
  else
    echo "$HOSTS_FILE 无需修改（Hosts 屏蔽已关闭）。"
  fi
}

print_status_compact() {
  local hosts_state
  hosts_state="$(hosts_block_state)"

  local check_suppressed download_suppressed install_macos_suppressed commerce_suppressed schedule_suppressed attention_state
  check_suppressed="$(read_defaults_suppressed /Library/Preferences/com.apple.SoftwareUpdate AutomaticCheckEnabled 关)"
  download_suppressed="$(read_defaults_suppressed /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload 关)"
  install_macos_suppressed="$(read_defaults_suppressed /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates 关)"
  commerce_suppressed="$(read_defaults_suppressed /Library/Preferences/com.apple.commerce AutoUpdate 关)"
  schedule_suppressed="$(softwareupdate_schedule_onoff)"
  attention_state="$(read_defaults_key_present_onoff /Library/Preferences/com.apple.systempreferences AttentionPrefBundleIDs)"

  echo "当前状态:"
  echo "  Hosts 屏蔽:              $hosts_state"
  echo "  禁止自动检查更新:        $check_suppressed"
  echo "  禁止自动下载更新:        $download_suppressed"
  echo "  禁止自动安装 macOS:      $install_macos_suppressed"
  echo "  禁止 App Store 自动更新: $commerce_suppressed"
  echo "  软件更新计划任务:        $schedule_suppressed (系统保护，可能无法关闭)"
  echo "  系统设置角标已覆盖:      $attention_state"
}

print_status_full() {
  print_status_compact
  echo ""
  echo "Hosts 标记:"
  if [[ -f "$HOSTS_FILE" ]]; then
    case "$(active_markers)" in
      NEW)
        echo "  已存在 $START_MARK ... $END_MARK"
        ;;
      LEGACY)
        echo "  检测到旧标记（下次应用/还原时会自动迁移）"
        ;;
      BOTH)
        echo "  同时存在新旧标记（下次应用/还原时会自动规范化）"
        ;;
      *)
        echo "  未检测到"
        ;;
    esac
  else
    echo "  未找到 $HOSTS_FILE"
  fi
}

disable_update_prompts() {
  is_root || { need_root_msg; return 2; }
  # 关闭自动检查/下载/安装（尽力而为）。
  defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticCheckEnabled -bool FALSE
  defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload -bool FALSE
  defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates -bool FALSE
  defaults write /Library/Preferences/com.apple.SoftwareUpdate CriticalUpdateInstall -bool FALSE
  defaults write /Library/Preferences/com.apple.commerce AutoUpdate -bool FALSE

  # 关闭 softwareupdate 计划任务（尽力而为，较新 macOS 可能不生效）。
  /usr/sbin/softwareupdate --schedule off >/dev/null 2>&1 || true

  # 尝试清理/隐藏系统设置中的"注意/角标"提示（尽力而为）。
  defaults write /Library/Preferences/com.apple.systempreferences AttentionPrefBundleIDs 0 >/dev/null 2>&1 || true
}

restore_update_prompts() {
  is_root || { need_root_msg; return 2; }
  # 尽力还原：重新开启相关开关，并移除角标覆盖。
  defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticCheckEnabled -bool TRUE
  defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload -bool TRUE
  defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates -bool TRUE
  defaults write /Library/Preferences/com.apple.SoftwareUpdate CriticalUpdateInstall -bool TRUE
  defaults write /Library/Preferences/com.apple.commerce AutoUpdate -bool TRUE

  /usr/sbin/softwareupdate --schedule on >/dev/null 2>&1 || true

  defaults delete /Library/Preferences/com.apple.systempreferences AttentionPrefBundleIDs >/dev/null 2>&1 || true
}

interactive_menu() {
  while true; do
    echo ""
    print_status_compact
    echo ""
    echo "请选择操作："
    echo "  1) 应用 Hosts 屏蔽"
    echo "  2) 还原 Hosts（移除屏蔽）"
    echo "  3) 应用更新提示抑制"
    echo "  4) 还原更新提示"
    echo "  5) 应用全部"
    echo "  6) 还原全部"
    echo "  7) 显示完整状态"
    echo "  0) 退出"
    printf "> "
    read -r choice
    case "$choice" in
      1)
        enable_hosts_block || true
        ;;
      2)
        disable_hosts_block || true
        ;;
      3)
        if disable_update_prompts; then
          echo "已应用“软件更新提示抑制”（尽力而为）。"
          echo "可能需要重启后才能完全生效。"
        fi
        ;;
      4)
        if restore_update_prompts; then
          echo "已还原“软件更新提示”相关设置（尽力而为）。"
          echo "可能需要重启后才能完全生效。"
        fi
        ;;
      5)
        enable_hosts_block || true
        if disable_update_prompts; then
          echo "已应用“软件更新提示抑制”（尽力而为）。"
          echo "可能需要重启后才能完全生效。"
        fi
        ;;
      6)
        disable_hosts_block || true
        if restore_update_prompts; then
          echo "已还原“软件更新提示”相关设置（尽力而为）。"
          echo "可能需要重启后才能完全生效。"
        fi
        ;;
      7)
        echo ""
        print_status_full
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

INTERACTIVE=0
STATUS_ONLY=0
ENABLE_HOSTS=0
DISABLE_HOSTS=0
DISABLE_UPDATE_PROMPTS=0
RESTORE_UPDATE_PROMPTS=0

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
      --enable-hosts|--apply-hosts)
        ENABLE_HOSTS=1
        ;;
      --disable-hosts|--remove-hosts)
        DISABLE_HOSTS=1
        ;;
      --disable-update-prompts)
        DISABLE_UPDATE_PROMPTS=1
        ;;
      --restore-update-prompts)
        RESTORE_UPDATE_PROMPTS=1
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

if [[ "$DISABLE_UPDATE_PROMPTS" -eq 1 && "$RESTORE_UPDATE_PROMPTS" -eq 1 ]]; then
  echo "错误：不能同时使用 --disable-update-prompts 与 --restore-update-prompts。" >&2
  exit 2
fi

if [[ "$ENABLE_HOSTS" -eq 1 && "$DISABLE_HOSTS" -eq 1 ]]; then
  echo "错误：不能同时使用 --enable-hosts 与 --disable-hosts。" >&2
  exit 2
fi

if [[ "$INTERACTIVE" -eq 1 ]]; then
  interactive_menu
fi

if [[ "$STATUS_ONLY" -eq 1 ]]; then
  print_status_full
  exit 0
fi

did_anything=0

if [[ "$ENABLE_HOSTS" -eq 1 ]]; then
  enable_hosts_block
  did_anything=1
fi

if [[ "$DISABLE_HOSTS" -eq 1 ]]; then
  disable_hosts_block
  did_anything=1
fi

if [[ "$DISABLE_UPDATE_PROMPTS" -eq 1 ]]; then
  disable_update_prompts
  echo "已应用“软件更新提示抑制”（尽力而为）。"
  echo "可能需要重启后才能完全生效。"
  did_anything=1
fi

if [[ "$RESTORE_UPDATE_PROMPTS" -eq 1 ]]; then
  restore_update_prompts
  echo "已还原“软件更新提示”相关设置（尽力而为）。"
  echo "可能需要重启后才能完全生效。"
  did_anything=1
fi

if [[ "$did_anything" -eq 0 ]]; then
  usage >&2
  exit 2
fi
