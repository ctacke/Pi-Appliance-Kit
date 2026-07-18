#!/usr/bin/env bash
# Shared helpers for pi-appliance-kit. Dependency-free (awk + coreutils only).
# Sourced by scripts/apply.sh and reused by the pi-gen stage.

# ---- output ----------------------------------------------------------------
c_info()  { printf '\033[36m•\033[0m %s\n' "$*"; }
c_ok()    { printf '\033[32m✔\033[0m %s\n' "$*"; }
c_skip()  { printf '\033[90m–\033[0m %s\n' "$*"; }
c_warn()  { printf '\033[33m!\033[0m %s\n' "$*" >&2; }
c_err()   { printf '\033[31m✗\033[0m %s\n' "$*" >&2; }

# DRY_RUN=1 → print what would happen, change nothing.
run() {
  if [ "${DRY_RUN:-0}" = "1" ]; then
    printf '\033[90m[dry-run]\033[0m %s\n' "$*"
  else
    "$@"
  fi
}

# ---- minimal YAML readers (for our known, flat schema) ---------------------
# Print items of a top-level list `KEY:` — lines like "  - value".
# Strips inline "# comments" and surrounding quotes. Stops at next top-level key.
yaml_list() {
  local key="$1" file="$2"
  awk -v key="$key" '
    $0 ~ "^"key":[[:space:]]*$" { grab=1; next }
    grab && /^[^[:space:]#]/    { grab=0 }
    grab && /^[[:space:]]*-/ {
      sub(/^[[:space:]]*-[[:space:]]*/, "")
      sub(/[[:space:]]*#.*$/, "")
      gsub(/^["'"'"']|["'"'"']$/, "")
      if (length($0)) print
    }
  ' "$file"
}

# Read a scalar `NAME:` nested one level under `toggles:`. Echoes the value.
yaml_toggle() {
  local name="$1" file="$2"
  awk -v name="$name" '
    /^toggles:[[:space:]]*$/ { grab=1; next }
    grab && /^[^[:space:]#]/ { grab=0 }
    grab && $1 == name":" {
      sub(/^[[:space:]]*[^:]+:[[:space:]]*/, "")
      sub(/[[:space:]]*#.*$/, "")
      gsub(/^["'"'"']|["'"'"']$/, "")
      print; exit
    }
  ' "$file"
}

# ---- systemd helpers (idempotent) ------------------------------------------
unit_exists()   { systemctl list-unit-files "$1" >/dev/null 2>&1 && \
                  systemctl cat "$1" >/dev/null 2>&1; }

disable_unit() {
  local u="$1"
  systemctl list-unit-files "$u" >/dev/null 2>&1 || { c_skip "no unit: $u"; return 0; }
  if [ "$(systemctl is-enabled "$u" 2>/dev/null)" = "disabled" ]; then
    c_skip "already disabled: $u"; return 0
  fi
  run systemctl disable "$u" && c_ok "disabled: $u"
}

mask_unit() {
  local u="$1"
  if [ "$(systemctl is-enabled "$u" 2>/dev/null)" = "masked" ]; then
    c_skip "already masked: $u"; return 0
  fi
  run systemctl mask "$u" && c_ok "masked: $u"
}

enable_unit() {
  local u="$1"
  if [ "$(systemctl is-enabled "$u" 2>/dev/null)" = "enabled" ]; then
    c_skip "already enabled: $u"; return 0
  fi
  run systemctl enable "$u" && c_ok "enabled: $u"
}

# ---- apt helpers (idempotent) ----------------------------------------------
pkg_installed() { dpkg -s "$1" >/dev/null 2>&1; }

purge_pkg() {
  pkg_installed "$1" || { c_skip "not installed: $1"; return 0; }
  run apt-get purge -y "$1" && c_ok "purged: $1"
}

install_pkg() {
  pkg_installed "$1" && { c_skip "already installed: $1"; return 0; }
  run apt-get install -y "$1" && c_ok "installed: $1"
}

# ---- config file block editing (idempotent, marker-delimited) --------------
# Replaces (or appends) a block between BEGIN/END markers so re-runs don't dupe.
BEGIN_MARK="# >>> pi-appliance-kit >>>"
END_MARK="# <<< pi-appliance-kit <<<"

apply_block() {
  local file="$1"; shift
  local block; block="$(printf '%s\n' "$@")"
  [ -f "$file" ] || { c_warn "missing $file (skipping block)"; return 0; }
  if [ "${DRY_RUN:-0}" = "1" ]; then
    printf '\033[90m[dry-run]\033[0m would write pi-appliance-kit block to %s:\n%s\n' "$file" "$block"
    return 0
  fi
  local tmp; tmp="$(mktemp)"
  awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
    $0==b {skip=1} $0==e {skip=0; next} !skip {print}
  ' "$file" > "$tmp"
  { cat "$tmp"; printf '%s\n%s\n%s\n' "$BEGIN_MARK" "$block" "$END_MARK"; } > "$file"
  rm -f "$tmp"
  c_ok "updated block in $file"
}

# Append space-separated tokens to the single-line cmdline.txt (idempotent).
append_cmdline() {
  local file="$1"; shift
  [ -f "$file" ] || { c_warn "missing $file (skipping cmdline)"; return 0; }
  local line; line="$(cat "$file")"
  local tok added=0
  for tok in "$@"; do
    case " $line " in *" $tok "*) : ;; *) line="$line $tok"; added=1 ;; esac
  done
  if [ "$added" = "0" ]; then c_skip "cmdline already has all tokens"; return 0; fi
  run bash -c "printf '%s\n' \"$line\" > '$file'" && c_ok "updated $file"
}
