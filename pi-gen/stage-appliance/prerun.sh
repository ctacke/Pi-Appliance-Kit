#!/bin/bash -e
# pi-gen boilerplate: seed this stage's rootfs from the previous stage.
if [ ! -d "${ROOTFS_DIR}" ]; then
	copy_previous
fi
