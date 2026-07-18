#!/bin/bash -e
# pi-gen step: bake pi-appliance-kit into the image by running the SAME apply.sh
# used for existing devices (single code path), then wire up read-only root.
#
# ${ROOTFS_DIR} = target image root, ${STAGE_DIR} = this stage dir.
# REPO_DIR is exported by build.sh (points at the repo checkout).

# The repo content (scripts/config/overlay) is bundled into this stage's files/
# by CI so the stage is self-contained once pi-gen copies it into its work dir.
# Falls back to the repo root when running the build locally from the checkout.
FILES="${STAGE_DIR}/00-appliance/files"
if [ -d "${FILES}/scripts" ]; then
	REPO_DIR="${FILES}"
else
	REPO_DIR="${REPO_DIR:-$(cd "${STAGE_DIR}/../.." && pwd)}"
fi
DEST="${ROOTFS_DIR}/opt/pi-appliance-kit"

install -d "${DEST}"
cp -a "${REPO_DIR}/scripts" "${REPO_DIR}/config" "${REPO_DIR}/overlay" "${DEST}/"

# Run apply.sh inside the image chroot. apt/systemctl/enable all work under
# on_chroot. Firmware paths resolve to /boot/firmware inside the image.
on_chroot <<'EOF'
export DEBIAN_FRONTEND=noninteractive
cd /opt/pi-appliance-kit
bash scripts/apply.sh
# Wire the writable data partition + first-boot provisioner.
systemctl enable rpi-data-init.service data.mount || true
# Clean apt caches to shrink the image.
apt-get clean
rm -rf /var/lib/apt/lists/*
EOF

# Read-only overlay root (appliance-grade) — toggle honored from the manifest.
if grep -qE '^\s*readonly_root:\s*true' "${REPO_DIR}/config/optimizations.yaml"; then
	bash "${STAGE_DIR}/00-appliance/enable-overlayroot.sh" "${ROOTFS_DIR}"
fi

# Remove the baked-in copy of the repo scripts from the shipped image.
rm -rf "${ROOTFS_DIR}/opt/pi-appliance-kit/scripts" "${ROOTFS_DIR}/opt/pi-appliance-kit/config"
