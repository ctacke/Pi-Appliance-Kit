#!/usr/bin/env bash
# pi-appliance-kit — install (or update) your appliance app onto /data/app.
#
#   Local (run on the Pi):
#     sudo ./scripts/install-app.sh ./myapp
#   Remote (run from your workstation):
#     ./scripts/install-app.sh ./myapp pi@device.local
#
# Convention: <app-dir> must contain an executable entrypoint named `run`.
# Everything in <app-dir> is copied to /data/app; the app reads/writes its own
# config & data there. The app.service is pre-enabled, so a restart runs it.
#
#   --dry-run   show what would happen, change nothing
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$HERE/lib/common.sh"

DRY_RUN=0; ARGS=()
for a in "$@"; do case "$a" in --dry-run|-n) DRY_RUN=1 ;; *) ARGS+=("$a") ;; esac; done
export DRY_RUN

APP_DIR="${ARGS[0]:-}"
TARGET_HOST="${ARGS[1]:-}"     # empty = install locally
DEST="/data/app"

usage() { echo "usage: install-app.sh <app-dir> [user@host] [--dry-run]" >&2; exit 2; }
[ -n "$APP_DIR" ] || usage
[ -d "$APP_DIR" ] || { c_err "not a directory: $APP_DIR"; exit 1; }
if [ ! -x "$APP_DIR/run" ]; then
  c_err "missing executable entrypoint: $APP_DIR/run"
  c_info "create it (e.g. a script that starts your daemon) and: chmod +x $APP_DIR/run"
  exit 1
fi
# Normalize to a trailing slash so rsync copies contents, not the dir itself.
SRC="${APP_DIR%/}/"

if [ -n "$TARGET_HOST" ]; then
  # ---- remote install over SSH -------------------------------------------
  c_info "installing $SRC → $TARGET_HOST:$DEST"
  run rsync -a --delete --rsync-path="sudo rsync" "$SRC" "$TARGET_HOST:$DEST/"
  run ssh "$TARGET_HOST" "sudo chmod +x $DEST/run && sudo systemctl restart app.service"
  run ssh "$TARGET_HOST" "systemctl --no-pager --lines=0 status app.service" || true
  c_ok "installed & restarted on $TARGET_HOST"
else
  # ---- local install (on the Pi) -----------------------------------------
  [ "$DRY_RUN" = "1" ] || [ "$(id -u)" = "0" ] || { c_err "run as root (sudo) for local install"; exit 1; }
  c_info "installing $SRC → $DEST"
  run mkdir -p "$DEST"
  run rsync -a --delete "$SRC" "$DEST/"
  run chmod +x "$DEST/run"
  run systemctl restart app.service
  run systemctl --no-pager --lines=0 status app.service || true
  c_ok "installed & restarted"
fi

c_info "logs: journalctl -u app.service  (journald is volatile — log to /data to persist)"
