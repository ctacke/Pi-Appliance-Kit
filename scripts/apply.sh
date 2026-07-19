#!/usr/bin/env bash
# pi-appliance-kit — apply optimizations to a running Raspberry Pi OS Lite (Track B).
#
#   sudo ./scripts/apply.sh              # apply
#   sudo ./scripts/apply.sh --dry-run    # show what would change, touch nothing
#   sudo DATA_ONLY=1 ./scripts/apply.sh  # (reserved) subset flags via env
#
# Idempotent: safe to re-run. Reads config/optimizations.yaml as the source of truth.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
MANIFEST="${MANIFEST:-$REPO/config/optimizations.yaml}"
OVERLAY="$REPO/overlay"
# shellcheck source=lib/common.sh
. "$HERE/lib/common.sh"

# Firmware paths differ across releases; detect the real config.txt location.
FW_DIR="/boot/firmware"; [ -d "$FW_DIR" ] || FW_DIR="/boot"
CONFIG_TXT="$FW_DIR/config.txt"
CMDLINE_TXT="$FW_DIR/cmdline.txt"

DRY_RUN=0
for a in "$@"; do case "$a" in --dry-run|-n) DRY_RUN=1 ;; esac; done
export DRY_RUN

[ -f "$MANIFEST" ] || { c_err "manifest not found: $MANIFEST"; exit 1; }
if [ "$DRY_RUN" = "0" ] && [ "$(id -u)" != "0" ]; then
  c_err "must run as root (use sudo). Or pass --dry-run."; exit 1
fi
c_info "manifest: $MANIFEST   firmware: $FW_DIR   dry-run: $DRY_RUN"

t() { yaml_toggle "$1" "$MANIFEST"; }

# --- 1. overlay files -------------------------------------------------------
c_info "installing overlay files"
if [ "$DRY_RUN" = "0" ]; then
  (cd "$OVERLAY" && find . -type f -print0 | while IFS= read -r -d '' f; do
     dest="/${f#./}"; install -D -m 0644 "$OVERLAY/${f#./}" "$dest"
     case "$dest" in */bin/*) chmod 0755 "$dest" ;; esac
   done)
  c_ok "overlay files copied"
else
  c_skip "would copy overlay/ tree into /"
fi

# --- 2. packages ------------------------------------------------------------
c_info "packages"
if [ "$DRY_RUN" = "0" ]; then run apt-get update -qq || c_warn "apt update failed (offline?)"; fi
while IFS= read -r p; do
  # only purge dphys-swapfile when the swap toggle is on
  if [ "$p" = "dphys-swapfile" ] && [ "$(t disable_swap)" != "true" ]; then
    c_skip "keeping $p (disable_swap=false)"; continue
  fi
  purge_pkg "$p"
done < <(yaml_list purge "$MANIFEST")
while IFS= read -r p; do install_pkg "$p"; done < <(yaml_list install "$MANIFEST")
# dhcpcd replaces NetworkManager — enable it if we just installed it.
if pkg_installed dhcpcd5 || pkg_installed dhcpcd; then enable_unit dhcpcd.service || true; fi

# --- 3. services ------------------------------------------------------------
c_info "disabling services"
while IFS= read -r u; do disable_unit "$u"; done < <(yaml_list disable "$MANIFEST")

c_info "masking services"
if [ "$(t disable_swap)" = "true" ]; then
  while IFS= read -r u; do mask_unit "$u"; done < <(yaml_list mask "$MANIFEST")
fi

# ssh strategy
case "$(t keep_ssh)" in
  socket) run systemctl disable ssh.service 2>/dev/null || true
          enable_unit ssh.socket 2>/dev/null || c_warn "ssh.socket unavailable on this release" ;;
  late)   run systemctl disable ssh.service 2>/dev/null || true
          enable_unit ssh-late.service ;;
  off)    disable_unit ssh.service ;;
esac

# wifi strategy
if [ "$(t keep_wifi)" = "true" ] && [ "$(t wifi_startup)" = "late" ]; then
  run systemctl disable wpa_supplicant.service 2>/dev/null || true
  enable_unit wifi-late.service
fi

# avahi (mDNS / .local). When kept, start it LATE — off the boot critical path,
# to match the wifi/ssh-late strategy. avahi is only useful once the network is
# up (also deferred), so early start would just burn boot time.
if [ "$(t keep_avahi)" = "true" ]; then
  install_pkg avahi-daemon   # usually already present on Lite; ensures the unit exists
  run systemctl disable avahi-daemon.service avahi-daemon.socket 2>/dev/null || true
  enable_unit avahi-late.service
else
  disable_unit avahi-daemon.service
  run systemctl disable avahi-daemon.socket 2>/dev/null || true
fi

c_info "enabling units"
while IFS= read -r u; do enable_unit "$u"; done < <(yaml_list enable "$MANIFEST")

# Boot to multi-user.target, not graphical.target. app.service is WantedBy it and
# app-ready.target Requires it; a display app draws via DRM/fb under multi-user too.
if [ "$(systemctl get-default 2>/dev/null)" != "multi-user.target" ]; then
  run systemctl set-default multi-user.target >/dev/null 2>&1 && c_ok "default target: multi-user.target" \
    || c_warn "could not set default target"
else
  c_skip "default target already multi-user.target"
fi

# --- 4. journald ------------------------------------------------------------
if [ "$(t journald_storage)" = "volatile" ]; then
  run mkdir -p /etc/systemd/journald.conf.d
  apply_block /etc/systemd/journald.conf.d/00-appliance.conf "[Journal]" "Storage=volatile" "RuntimeMaxUse=16M"
fi

# --- 5. firmware config.txt + cmdline.txt -----------------------------------
c_info "firmware config"
mapfile -t CFG < <(yaml_list config_txt "$MANIFEST")
mapfile -t HW  < <(yaml_list hardware_overlays "$MANIFEST")
[ "$(t keep_uart_console)" = "true" ] && CFG+=("enable_uart=1")
apply_block "$CONFIG_TXT" "${CFG[@]}" "${HW[@]}"
mapfile -t CMD < <(yaml_list cmdline_txt "$MANIFEST")
append_cmdline "$CMDLINE_TXT" "${CMD[@]}"
# Belt-and-suspenders with disabling rpi-resize.service: strip the stock first-boot
# root-grow markers so root never expands to fill the card (keeps space for /data).
remove_cmdline "$CMDLINE_TXT" resize 'init=*init_resize.sh'

# --- 6. swap ----------------------------------------------------------------
if [ "$(t disable_swap)" = "true" ]; then
  run systemctl disable rpi-resize-swap-file.service 2>/dev/null || true
  [ -x /sbin/dphys-swapfile ] && run dphys-swapfile swapoff 2>/dev/null || true
fi

if [ "$DRY_RUN" = "0" ]; then run systemctl daemon-reload || true; fi
c_ok "done. Read-only root & /data partition are set up by the image build (Track A)"
c_info "reboot, then: /usr/local/bin/boot-benchmark.sh"
