#!/usr/bin/env bash

set -Eeuo pipefail

log() {
  printf '[INFO] %s\n' "$*"
}

warn() {
  printf '[WARN] %s\n' "$*" >&2
}

die() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "缺少命令: $1"
}

run_as_root() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    "$@"
  else
    need_cmd sudo
    sudo "$@"
  fi
}

detect_pkg_manager() {
  if command -v apt-get >/dev/null 2>&1; then
    echo "apt"
    return
  fi
  if command -v dnf >/dev/null 2>&1; then
    echo "dnf"
    return
  fi
  if command -v yum >/dev/null 2>&1; then
    echo "yum"
    return
  fi
  if command -v pacman >/dev/null 2>&1; then
    echo "pacman"
    return
  fi
  die "不支持的系统：未找到 apt/dnf/yum/pacman。"
}

repair_legacy_apt_sources() {
  local files=()
  local source_files=()
  local changed=0

  [[ -f /etc/apt/sources.list ]] && files+=("/etc/apt/sources.list")
  if [[ -d /etc/apt/sources.list.d ]]; then
    while IFS= read -r -d '' f; do
      files+=("$f")
    done < <(find /etc/apt/sources.list.d -maxdepth 1 -type f -name '*.list' -print0 2>/dev/null)

    while IFS= read -r -d '' f; do
      source_files+=("$f")
    done < <(find /etc/apt/sources.list.d -maxdepth 1 -type f -name '*.sources' -print0 2>/dev/null)
  fi

  for f in "${files[@]}"; do
    if grep -Eq '^[[:space:]]*deb(-src)?[[:space:]].*bullseye/updates([[:space:]]|$)' "$f"; then
      log "禁用失效的 bullseye/updates 源: $f"
      run_as_root sed -i -E \
        '/^[[:space:]]*deb(-src)?[[:space:]].*bullseye\/updates([[:space:]]|$)/s/^/# /' \
        "$f"
      changed=1
    fi

    if grep -Eq 'bullseye-backports' "$f"; then
      log "禁用失效的 bullseye-backports 源: $f"
      run_as_root sed -i -E \
        '/^[[:space:]]*deb(-src)?[[:space:]].*bullseye-backports/s/^/# /' \
        "$f"
      changed=1
    fi
  done

  for f in "${source_files[@]}"; do
    if grep -Eq '^[[:space:]]*Suites:[[:space:]]*bullseye/updates([[:space:]]|$)' "$f"; then
      log "修复 deb822 安全源 Suites: $f"
      run_as_root sed -i -E \
        's|^([[:space:]]*Suites:[[:space:]]*)bullseye/updates([[:space:]]|$)|\1bullseye-security\2|g' \
        "$f"
      changed=1
    fi

    if grep -Eq '^[[:space:]]*Suites:[[:space:]].*bullseye/updates' "$f"; then
      log "替换 deb822 中残留的 bullseye/updates: $f"
      run_as_root sed -i -E \
        's|bullseye/updates|bullseye-security|g' \
        "$f"
      changed=1
    fi

    if grep -Eq '^[[:space:]]*URIs:[[:space:]]*https?://security\.debian\.org/?[[:space:]]*$' "$f"; then
      log "修复 deb822 安全源 URI: $f"
      run_as_root sed -i -E \
        's|^([[:space:]]*URIs:[[:space:]]*https?://security\.debian\.org)/?[[:space:]]*$|\1/debian-security|g' \
        "$f"
      changed=1
    fi
  done

  if [[ "$changed" -eq 1 ]]; then
    return 0
  fi
  return 1
}

apt_update_with_retry() {
  if run_as_root apt-get update; then
    return 0
  fi

  warn "apt update 失败，尝试修复 Debian 旧源配置后重试..."
  if repair_legacy_apt_sources; then
    if run_as_root apt-get update; then
      return 0
    fi
  fi

  # 最后兜底：强制注释所有 bullseye/updates 并写入可用安全源
  warn "自动修复未完全生效，执行兜底安全源修复后重试..."
  run_as_root mkdir -p /etc/apt/sources.list.d
  run_as_root sh -c 'for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.list; do
    [ -f "$f" ] || continue
    sed -i -E "/^[[:space:]]*deb(-src)?[[:space:]].*bullseye\/updates([[:space:]]|$)/s/^/# /" "$f"
  done'
  run_as_root sh -c 'cat > /etc/apt/sources.list.d/99-bullseye-security-fix.list << "EOF"
deb http://security.debian.org/debian-security bullseye-security main
EOF'
  if run_as_root apt-get update; then
    return 0
  fi

  die "apt update 仍失败，请检查 /etc/apt/sources.list* 源配置。"
}

install_base_packages() {
  local pm="$1"
  log "检测到包管理器: $pm"
  case "$pm" in
    apt)
      apt_update_with_retry
      run_as_root apt-get install -y zsh curl git
      ;;
    dnf)
      run_as_root dnf install -y zsh curl git
      ;;
    yum)
      run_as_root yum install -y zsh curl git
      ;;
    pacman)
      run_as_root pacman -Sy --noconfirm zsh curl git
      ;;
    *)
      die "未知包管理器: $pm"
      ;;
  esac
}

resolve_target_user() {
  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    echo "${SUDO_USER}"
    return
  fi
  id -un
}

resolve_target_home() {
  local user="$1"
  local home_dir
  if command -v getent >/dev/null 2>&1; then
    home_dir="$(getent passwd "$user" | awk -F: '{print $6}')"
  else
    home_dir="$(eval echo "~${user}")"
  fi
  if [[ -z "$home_dir" ]]; then
    die "无法解析用户 $user 的 HOME 目录。"
  fi
  echo "$home_dir"
}

run_as_target_user() {
  local user="$1"
  shift
  if [[ "$(id -un)" == "$user" ]]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo -H -u "$user" "$@"
  elif [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    local cmd
    cmd="$(printf '%q ' "$@")"
    su - "$user" -c "$cmd"
  else
    die "当前用户不是目标用户且缺少 sudo，无法切换到 $user 执行命令。"
  fi
}

set_default_shell() {
  local user="$1"
  local zsh_bin="$2"
  local current_shell

  if command -v getent >/dev/null 2>&1; then
    current_shell="$(getent passwd "$user" | awk -F: '{print $7}')"
  else
    current_shell="$(grep "^${user}:" /etc/passwd | awk -F: '{print $7}')"
  fi
  if [[ "$current_shell" == "$zsh_bin" ]]; then
    log "用户 $user 默认 shell 已是 $zsh_bin，跳过切换。"
    return
  fi

  if ! command -v chsh >/dev/null 2>&1; then
    warn "系统无 chsh，无法自动切换默认 shell。请手动执行: chsh -s $zsh_bin"
    return
  fi

  log "为用户 $user 设置默认 shell: $zsh_bin"
  run_as_root chsh -s "$zsh_bin" "$user"
}

install_oh_my_zsh() {
  local user="$1"
  local home_dir="$2"
  local ohmyzsh_dir="${home_dir}/.oh-my-zsh"

  if [[ -d "$ohmyzsh_dir" ]]; then
    log "Oh My Zsh 已安装，跳过。"
    return
  fi

  log "安装 Oh My Zsh..."
  run_as_target_user "$user" sh -c \
    'RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"'
}

install_plugins() {
  local user="$1"
  local home_dir="$2"
  local custom_dir="${home_dir}/.oh-my-zsh/custom"

  local autosuggest_dir="${custom_dir}/plugins/zsh-autosuggestions"
  local syntax_dir="${custom_dir}/plugins/zsh-syntax-highlighting"

  if [[ -d "$autosuggest_dir" ]]; then
    log "插件 zsh-autosuggestions 已存在，跳过。"
  else
    log "安装插件 zsh-autosuggestions..."
    run_as_target_user "$user" git clone \
      https://github.com/zsh-users/zsh-autosuggestions \
      "$autosuggest_dir"
  fi

  if [[ -d "$syntax_dir" ]]; then
    log "插件 zsh-syntax-highlighting 已存在，跳过。"
  else
    log "安装插件 zsh-syntax-highlighting..."
    run_as_target_user "$user" git clone \
      https://github.com/zsh-users/zsh-syntax-highlighting.git \
      "$syntax_dir"
  fi
}

update_zshrc() {
  local user="$1"
  local home_dir="$2"
  local zshrc="${home_dir}/.zshrc"
  local template="${home_dir}/.oh-my-zsh/templates/zshrc.zsh-template"

  if [[ ! -f "$zshrc" ]]; then
    if [[ -f "$template" ]]; then
      log "检测到缺少 ~/.zshrc，使用模板创建。"
      run_as_target_user "$user" cp "$template" "$zshrc"
    else
      run_as_target_user "$user" touch "$zshrc"
    fi
  fi

  log "配置插件和主题..."
  run_as_target_user "$user" sed -i -E \
    's/^plugins=.*/plugins=(git zsh-autosuggestions zsh-syntax-highlighting)/' \
    "$zshrc"

  if ! run_as_target_user "$user" grep -Eq '^plugins=' "$zshrc"; then
    run_as_target_user "$user" sh -c \
      "printf '\nplugins=(git zsh-autosuggestions zsh-syntax-highlighting)\n' >> '$zshrc'"
  fi

  run_as_target_user "$user" sed -i -E 's/^ZSH_THEME=.*/ZSH_THEME="ys"/' "$zshrc"
  if ! run_as_target_user "$user" grep -Eq '^ZSH_THEME=' "$zshrc"; then
    run_as_target_user "$user" sh -c "printf '\nZSH_THEME=\"ys\"\n' >> '$zshrc'"
  fi

  log "尝试刷新 zsh 配置..."
  run_as_target_user "$user" zsh -ic 'source ~/.zshrc >/dev/null 2>&1 || true'
}

main() {
  local pm
  local user
  local home_dir
  local zsh_bin

  pm="$(detect_pkg_manager)"
  install_base_packages "$pm"

  zsh_bin="$(command -v zsh || true)"
  [[ -n "$zsh_bin" ]] || die "zsh 安装后仍未找到可执行文件。"

  log "zsh 版本: $("$zsh_bin" --version)"

  user="$(resolve_target_user)"
  home_dir="$(resolve_target_home "$user")"

  set_default_shell "$user" "$zsh_bin"
  install_oh_my_zsh "$user" "$home_dir"
  install_plugins "$user" "$home_dir"
  update_zshrc "$user" "$home_dir"

  log "全部流程执行完成。"
  log "请重新登录 SSH 会话后执行: echo \$SHELL"
  log "若输出为 $zsh_bin（或同路径），则默认 shell 已切换成功。"
}

main "$@"
