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

# on_chroot is exported by pi-gen's build environment (export -f on_chroot). Only
# stub it out when we're NOT inside pi-gen (standalone run), so we never clobber
# the real function — doing so would silently skip read-only root entirely.
if ! declare -F on_chroot >/dev/null 2>&1; then
  echo "WARN: on_chroot unavailable (not inside pi-gen); read-only root NOT enabled."
  on_chroot() { :; }
fi

# pi-gen's on_chroot already execs 'bash -e' inside the chroot and reads the
# script from stdin — feed the heredoc directly, do NOT pass 'bash' as an arg.
on_chroot <<'EOF'
if command -v raspi-config >/dev/null 2>&1; then
  raspi-config nonint enable_overlayfs || echo "WARN: enable_overlayfs failed; verify on hardware"
  raspi-config nonint enable_bootro   || echo "WARN: enable_bootro failed; boot stays rw"
else
  echo "WARN: raspi-config absent; read-only root NOT enabled. See docs."
fi
EOF
