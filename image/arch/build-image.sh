#!/bin/bash
# Build the complete Arch Linux ARM system for the Redmi 8 from scratch.
#
#   scripts/build/build-kernel.sh          # first: kernel and modules
#   sudo image/arch/build-image.sh         # then: this
#
# On an x86_64 host install qemu-user-static; on aarch64 it is not needed.
# A user namespace with binfmt_misc works too, for hosts without sudo.
#
# Output in dist/image/ (flash with scripts/flash/flash.py):
#   userdata.img   Android sparse image of a whole disk: an MBR with
#                  p1 = /boot (ext2: extlinux, kernel, initramfs, DTB) and
#                  p2 = / (ext4)                          -> userdata
#   lk2nd.img      the second-stage bootloader            -> boot
#   SHA256SUMS
#
# Inputs, from the environment:
#   KERNEL_DIR  staged kernel from build-kernel.sh (default ~/redmi8-build/kernel
#               of the user who called sudo)
#   WORK        scratch space on a Linux filesystem (default /var/tmp/redmi8-image-arch)
#   REUSE_ROOTFS 1: continue with the pacman rootfs already in $WORK/rootfs
#               instead of unpacking the tarball again (for a failed build)
#   ALARM_MIRROR, ALARM_TARBALL, PACMAN_INSECURE
# plus the user/password/locale settings described in image/arch/lib.sh.
# Optional features are not installed: see extras/.
set -euo pipefail
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
. "$REPO/image/arch/lib.sh"
if [ -n "${SUDO_USER:-}" ]; then
	CALLER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
	CALLER_HOME=$HOME
fi
KERNEL_DIR=${KERNEL_DIR:-$CALLER_HOME/redmi8-build/kernel}
WORK=${WORK:-/var/tmp/redmi8-image-arch}
OUT=${OUT:-$REPO/dist/image}
ALARM_MIRROR=${ALARM_MIRROR:-http://mirror.archlinuxarm.org}
KREL=7.1.3-msm89x7-olive-r7

# msm-firmware-loader (postmarketOS, MIT): links the firmware on the phone's
# Android partitions for the kernel. Pinned to the release the reference
# phone runs.
MFL_URL=https://gitlab.postmarketos.org/postmarketOS/msm-firmware-loader/-/raw/1.8.0
MFL_SH_SHA256=08588c255e31fdb5eafe8bb0f87f032231b86011623e799c473c65ac2fa2a737
MFL_SERVICE_SHA256=aced9d40777a9c3dfb923e713bce7661fb9bf74680603ed5b3acdbe4f304a96a

require_host
[ -f "$KERNEL_DIR/vmlinuz" ] && [ -d "$KERNEL_DIR/modules/lib/modules/$KREL" ] ||
	die "no staged kernel in $KERNEL_DIR - run scripts/build/build-kernel.sh first (or set KERNEL_DIR)"
image_settings redmi8
R=$WORK/rootfs
BOOT=$WORK/boot
ROOT_UUID=$(cat /proc/sys/kernel/random/uuid)
BOOT_UUID=$(cat /proc/sys/kernel/random/uuid)
trap chroot_umount EXIT

if [ "${REUSE_ROOTFS:-0}" = 1 ] && [ -x "$R/usr/bin/pacman" ]; then
	log "reusing $R"
else
	rootfs_bootstrap "$R"
fi
chroot_mount "$R"
ensure_binfmt
rootfs_install "$R" "$REPO/device/arch/packages.txt"
rootfs_configure "$R"

log "kernel modules and firmware"
rm -rf "$R/usr/lib/modules/$KREL"
mkdir -p "$R/usr/lib/modules"
cp -a "$KERNEL_DIR/modules/lib/modules/$KREL" "$R/usr/lib/modules/"
chown -R 0:0 "$R/usr/lib/modules/$KREL"
in_chroot "$R" depmod -a "$KREL"
copy_tree "$REPO/firmware/qcom" "$R/usr/lib/firmware/qcom"
install -D -m 644 "$REPO/firmware/ilitek/olive-ili9881h-c3i-0x04.ili" \
	"$R/usr/lib/firmware/ilitek/olive-ili9881h-c3i-0x04.ili"
install -m 644 "$KERNEL_DIR/config" "$R/boot/config-$KREL"

log "msm-firmware-loader 1.8.0"
curl -fsSL "$MFL_URL/msm-firmware-loader.sh" -o "$WORK/msm-firmware-loader.sh"
curl -fsSL "$MFL_URL/msm-firmware-loader.service" -o "$WORK/msm-firmware-loader.service"
echo "$MFL_SH_SHA256  $WORK/msm-firmware-loader.sh" | sha256sum -c - >/dev/null ||
	die "msm-firmware-loader.sh checksum mismatch"
echo "$MFL_SERVICE_SHA256  $WORK/msm-firmware-loader.service" | sha256sum -c - >/dev/null ||
	die "msm-firmware-loader.service checksum mismatch"
install -m 755 "$WORK/msm-firmware-loader.sh" "$R/usr/sbin/msm-firmware-loader.sh"
install -m 644 "$WORK/msm-firmware-loader.service" "$R/etc/systemd/system/msm-firmware-loader.service"

rootfs_device "$R" "$REPO/device/base" "$REPO/device/arch/base" "$REPO/device/arch/configure.sh"

cat > "$R/etc/fstab" <<EOF
# Both live in the disk image on userdata (loop device, see the initramfs).
UUID=$ROOT_UUID  /      ext4  defaults,noatime  0 0
UUID=$BOOT_UUID  /boot  ext2  defaults,noatime,nofail  0 0
EOF

log "initramfs"
in_chroot "$R" mkinitcpio -k "$KREL" -c /etc/mkinitcpio.conf -g /boot/initramfs-olive.img

log "boot partition"
rm -rf "$BOOT"
mkdir -p "$BOOT/arch" "$BOOT/extlinux"
install -m 644 "$KERNEL_DIR/vmlinuz" "$BOOT/arch/vmlinuz"
install -m 644 "$R/boot/initramfs-olive.img" "$BOOT/arch/initramfs"
install -m 644 "$REPO/kernel/devicetree/sdm439-xiaomi-olive.dtb" "$BOOT/arch/sdm439-xiaomi-olive.dtb"
cat > "$BOOT/extlinux/extlinux.conf" <<EOF
timeout 2
default arch
menu title Redmi 8 (Arch Linux ARM)

label arch
    kernel /arch/vmlinuz
    fdtdir /arch
    initrd /arch/initramfs
    append root=UUID=$ROOT_UUID rw rootwait panic=10 softlockup_panic=1 hung_task_panic=1 hung_task_timeout_secs=90 quiet
EOF
# /boot of the root filesystem is only the mount point of p1.
rm -rf "$R"/boot/*

rootfs_finish "$R"
chroot_umount

log "disk image"
mkdir -p "$OUT"
rm -f "$OUT/userdata.img" "$OUT/SHA256SUMS"
mke2fs -q -F -t ext2 -b 4096 -L pmOS_boot -U "$BOOT_UUID" -d "$BOOT" "$WORK/boot.ext2" 512M
e2fsck -fn "$WORK/boot.ext2" >/dev/null
# lk2nd finds extlinux.conf on the first partition of this disk image; the
# labels are the ones lk2nd and earlier images use.
make_ext4 "$R" "$WORK/root.ext4" pmOS_root "$ROOT_UUID"
ROOT_MB=$(( $(stat -c %s "$WORK/root.ext4") / 1048576 ))
RAW=$WORK/userdata.raw
rm -f "$RAW"
truncate -s $(( (1 + 512 + ROOT_MB) * 1048576 )) "$RAW"
sfdisk -q "$RAW" <<EOF
label: dos
start=2048, size=1048576, type=83
start=1050624, type=83
EOF
dd if="$WORK/boot.ext2" of="$RAW" bs=1M seek=1 conv=notrunc,sparse status=none
dd if="$WORK/root.ext4" of="$RAW" bs=1M seek=513 conv=notrunc,sparse status=none
rm -f "$WORK/boot.ext2" "$WORK/root.ext4"
sparse_image "$RAW" "$OUT/userdata.img"
rm -f "$RAW"

WORK="$WORK/lk2nd" OUT="$OUT" "$REPO/image/build-lk2nd.sh"
# Minimal DTBO for the stock bootloader: with the stock overlay it refuses
# to start lk2nd on SDM439 and drops back to fastboot.
install -m 644 "$REPO/firmware/dtbo/dtbo-xiaomi-olive.img" "$OUT/dtbo.img"
checksums "$OUT"
log "done: flash with scripts/flash/flash.py (docs/03-installing.md)"
