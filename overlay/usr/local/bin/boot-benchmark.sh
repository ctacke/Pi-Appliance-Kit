#!/usr/bin/env bash
# pi-appliance-kit — record real boot timings after each boot.
# Logs to /data/boot-benchmark.log (persistent) so you get a before/after trail
# even with a read-only root. Also prints a summary to stdout.
set -euo pipefail

LOG_DIR="${LOG_DIR:-/data}"; [ -w "$LOG_DIR" ] || LOG_DIR="/tmp"
LOG="$LOG_DIR/boot-benchmark.log"
STAMP="$(date -Is)"

overall="$(systemd-analyze 2>/dev/null || echo 'n/a')"

# Time to our real appliance marker, if present.
app_ready="n/a"
if systemctl list-unit-files app-ready.target >/dev/null 2>&1; then
  ts="$(systemd-analyze --property=ActiveEnterTimestampMonotonic \
        show app-ready.target 2>/dev/null | cut -d= -f2 || true)"
  [ -n "${ts:-}" ] && [ "$ts" != "0" ] && \
    app_ready="$(awk -v us="$ts" 'BEGIN{printf "%.3fs", us/1000000}')"
fi

{
  echo "=== $STAMP ==="
  echo "$overall"
  echo "app-ready.target: $app_ready"
  echo "--- top 10 blame ---"
  systemd-analyze blame 2>/dev/null | head -n 10 || true
  echo
} | tee -a "$LOG"

echo "logged to $LOG"
