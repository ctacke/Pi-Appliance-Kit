#!/bin/bash -e
# pi-appliance-kit — enable the read-only overlay root in the image being built.
#
# We delegate to raspi-config's OWN maintained, version-correct implementation
# (enable_overlayfs builds an initramfs overlay hook + patches cmdline; enable_bootro
# makes the boot partition read-only). Hand-rolling an initramfs premount hook here
# would rot across Raspberry Pi OS releases — this does not.
#
# The writable /data partition (see data.mount / rpi-data-init) is unaffected:
# it's a real, separately-mounted ext4 partition, so app config/data persist even
# though the OS root discards writes on power-off.
ROOTFS_DIR="$1"

on_chroot() { :; }  # provided by pi-gen when sourced; noop guard if run standalone
if command -v capsh >/dev/null 2>&1 || [ -n "${STAGE_DIR:-}" ]; then
  # Inside pi-gen: on_chroot is defined by the build environment.
  on_chroot bash -e <<'EOF'
if command -v raspi-config >/dev/null 2>&1; then
  raspi-config nonint enable_overlayfs || echo "WARN: enable_overlayfs failed; verify on hardware"
  raspi-config nonint enable_bootro   || echo "WARN: enable_bootro failed; boot stays rw"
else
  echo "WARN: raspi-config absent; read-only root NOT enabled. See docs."
fi
EOF
fi
