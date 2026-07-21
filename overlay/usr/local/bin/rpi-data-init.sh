#!/usr/bin/env bash
# pi-appliance-kit — first-boot provisioning of the writable /data partition.
# Creates a 3rd partition in the SD card's free space (after root), formats it
# ext4 labeled "data", then hands off to data.mount. Idempotent: if a partition
# labeled "data" already exists, it does nothing. Runs BEFORE root goes
# read-only (ordered by rpi-data-init.service).
set -euo pipefail

# The appliance login that owns /data (so the app can read/write without root).
APP_USER="${APP_USER:-pi}"

# Give $APP_USER ownership of the filesystem root of the data partition. Runs
# BEFORE data.mount, so the fs isn't mounted yet — mount it privately, chown,
# unmount. Cheap and idempotent on later boots.
ensure_owner() {
  local part="$1" mnt
  id "$APP_USER" >/dev/null 2>&1 || return 0
  mnt="$(mktemp -d)"
  mount "$part" "$mnt"
  chown "$APP_USER":"$APP_USER" "$mnt"
  chmod 0775 "$mnt"
  umount "$mnt"
  rmdir "$mnt"
}

# Already provisioned? (label present) — still make sure $APP_USER owns it.
if DATA_PART="$(blkid -L data 2>/dev/null)"; then
  ensure_owner "$DATA_PART"
  exit 0
fi

# Find the root block device (e.g. /dev/mmcblk0) and root partition number.
ROOT_PART="$(findmnt -no SOURCE / || true)"          # e.g. /dev/mmcblk0p2
case "$ROOT_PART" in
  *[0-9]p[0-9]*) DISK="${ROOT_PART%p*}"; PNUM="${ROOT_PART##*p}" ;;  # mmcblk0p2
  *)             DISK="${ROOT_PART%%[0-9]*}"; PNUM="${ROOT_PART##*[!0-9]}" ;;  # sda2
esac
[ -b "$DISK" ] || { echo "rpi-data-init: cannot resolve disk from $ROOT_PART"; exit 0; }

DATA_NUM=$((PNUM + 1))
# If that partition slot already exists (e.g. a pre-baked data part), just format.
DATA_PART="$(lsblk -rno NAME "$DISK" | sed -n "$((DATA_NUM+1))p" | awk '{print "/dev/"$1}')"

if [ ! -b "${DATA_PART:-/nonexistent}" ]; then
  echo "rpi-data-init: creating partition $DATA_NUM on $DISK"
  # Start right after the root partition, use all remaining space.
  parted -s "$DISK" -- unit MB print >/dev/null 2>&1 || true
  START="$(parted -sm "$DISK" unit MB print | awk -F: -v n="$PNUM" '$1==n{gsub(/MB/,"",$3); print $3+1}')"
  parted -s "$DISK" -- mkpart primary ext4 "${START}MB" 100%
  partprobe "$DISK" || true
  sleep 1
  case "$DISK" in *mmcblk*|*nvme*) DATA_PART="${DISK}p${DATA_NUM}" ;; *) DATA_PART="${DISK}${DATA_NUM}" ;; esac
fi

echo "rpi-data-init: formatting $DATA_PART as ext4 label=data"
mkfs.ext4 -F -L data "$DATA_PART"
mkdir -p /data
ensure_owner "$DATA_PART"
echo "rpi-data-init: done"
