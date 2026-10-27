# Shared image-building functions for the Arch Linux ARM build of the
# Redmi 8 image. Sourced by image/arch/build-image.sh; not meant to be run.
#
# There is no debootstrap here: the ArchLinuxARM aarch64 tarball is unpacked,
# upgraded with pacman and configured inside a chroot. On an x86_64 build
# host qemu-user-static runs the aarch64 binaries (binfmt_misc), so only
# qemu-user-static is needed on top of the usual filesystem tools.
#
# Settings, all from the environment:
#   IMAGE_USER       login name                       (default: arch)
#   IMAGE_PASSWORD   its password, at least 8 chars   (asked for if unset)
#   IMAGE_HOSTNAME   host name                        (default: the device)
#   IMAGE_TIMEZONE   e.g. Europe/Berlin               (default: Etc/UTC)
#   IMAGE_LOCALE     e.g. de_DE.UTF-8                 (default: en_US.UTF-8)
#   IMAGE_KEYMAP     keyboard layout, e.g. de         (default: us)
#   SSH_PUBKEY       a public key file; if set, SSH accepts only keys
#   ALARM_MIRROR     default http://mirror.archlinuxarm.org
#   ALARM_TARBALL    use an already downloaded ArchLinuxARM-aarch64 tarball
#   PACMAN_INSECURE  set to 1 to pass curl -k (a mirror with a bad certificate)
#
# The caller (build-image.sh) must be root, or root in a user namespace that
# also owns binfmt_misc; the chroot mounts are made and removed here.

log() { printf '\n=== %s ===\n' "$*"; }
die() { echo "ERROR: $*" >&2; exit 1; }
ALARM_MIRROR=${ALARM_MIRROR:-http://mirror.archlinuxarm.org}

# require_host [extra tools...]
require_host() {
	[ "$(id -u)" = 0 ] || die "run as root (chroot, mke2fs and loop files need it)"
	local t
	for t in curl tar mke2fs e2fsck sfdisk python3 openssl sha256sum xz "$@"; do
		command -v "$t" >/dev/null || die "missing host tool: $t (see docs, 'Build host')"
	done
	if [ "$(uname -m)" != aarch64 ]; then
		[ -x "${QEMU_AARCH64_STATIC:-/usr/bin/qemu-aarch64-static}" ] ||
			die "missing ${QEMU_AARCH64_STATIC:-/usr/bin/qemu-aarch64-static} (package qemu-user-static on Arch)"
	fi
}

# image_settings <default hostname>
image_settings() {
	IMAGE_USER=${IMAGE_USER:-arch}
	IMAGE_HOSTNAME=${IMAGE_HOSTNAME:-$1}
	IMAGE_TIMEZONE=${IMAGE_TIMEZONE:-Etc/UTC}
	IMAGE_LOCALE=${IMAGE_LOCALE:-en_US.UTF-8}
	IMAGE_KEYMAP=${IMAGE_KEYMAP:-us}
	case "$IMAGE_USER" in root|"") die "IMAGE_USER must be a normal user name" ;; esac
	if [ -z "${IMAGE_PASSWORD:-}" ]; then
		[ -t 0 ] || die "set IMAGE_PASSWORD, or run the build in a terminal to be asked"
		local a b
		read -rsp "Password for '$IMAGE_USER' on the phone: " a; echo
		read -rsp "Repeat: " b; echo
		[ "$a" = "$b" ] || die "the passwords differ"
		IMAGE_PASSWORD=$a
	fi
	[ "${#IMAGE_PASSWORD}" -ge 8 ] || die "use a password of at least 8 characters"
	IMAGE_PASSWORD_HASH=$(printf '%s\n' "$IMAGE_PASSWORD" | openssl passwd -6 -stdin)
	unset IMAGE_PASSWORD
	IMAGE_SSH_KEY=
	if [ -n "${SSH_PUBKEY:-}" ]; then
		IMAGE_SSH_KEY=$(head -n1 "$SSH_PUBKEY")
		case "$IMAGE_SSH_KEY" in
		ssh-ed25519\ *|ssh-rsa\ *|ecdsa-sha2-*|sk-ssh-ed25519@openssh.com\ *) ;;
		*) die "$SSH_PUBKEY does not look like an SSH public key" ;;
		esac
	fi
}

# copy_tree <src dir> <dst dir>: modes as in the repository, owner root.
# --keep-directory-symlink: Arch also has /lib, /bin and /sbin as symlinks
# into /usr; replacing them with directories would break the image.
copy_tree() {
	tar -C "$1" --owner=0 --group=0 --numeric-owner -cf - . |
		tar -C "$2" --keep-directory-symlink -xpf -
}

_mounts=()
chroot_mount() {
	local R=$1 m
	for m in proc sys dev dev/pts run; do mkdir -p "$R/$m"; done
	mount -t proc proc "$R/proc"
	# sysfs cannot be mounted inside a user namespace; the host's is enough
	# for mkinitcpio and udev helpers there.
	mount -t sysfs sysfs "$R/sys" 2>/dev/null || mount --rbind /sys "$R/sys"
	# a bind mount of /dev is not allowed in a user namespace, --rbind is
	mount --rbind /dev "$R/dev"
	mount -t devpts devpts "$R/dev/pts" 2>/dev/null || true
	mount -t tmpfs tmpfs "$R/run"
	mkdir -p "$R/run/systemd/resolve"
	cp /etc/resolv.conf "$R/run/systemd/resolve/resolv.conf"
	_mounts=("$R/run" "$R/dev/pts" "$R/dev" "$R/sys" "$R/proc")
}

chroot_umount() {
	local m
	for m in "${_mounts[@]}"; do umount -l "$m" 2>/dev/null || true; done
	_mounts=()
}

in_chroot() {
	local R=$1; shift
	chroot "$R" /usr/bin/env -i PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
		HOME=/root USER=root LOGNAME=root TERM=dumb LANG=C LC_ALL=C "$@"
}

# ensure_binfmt: make the host run aarch64 binaries through qemu-user-static.
# The 4-byte magic at offset 18 (the low byte of e_machine, 0xb7) is used
# instead of the full ELF magic: it is accepted by every kernel, including
# ones whose binfmt_misc truncates the magic at the first NUL byte.
ensure_binfmt() {
	[ "$(uname -m)" = aarch64 ] && return 0
	local qemu=${QEMU_AARCH64_STATIC:-/usr/bin/qemu-aarch64-static}
	local mnt=${BINFMT_DIR:-/proc/sys/fs/binfmt_misc}
	[ -x "$qemu" ] || die "missing $qemu"
	if [ ! -e "$mnt/register" ]; then
		mkdir -p "$mnt" 2>/dev/null || true
		mount -t binfmt_misc binfmt_misc "$mnt" 2>/dev/null || true
	fi
	if [ ! -e "$mnt/register" ]; then
		# procfs under a user namespace (or a read-only /proc/sys) cannot
		# become a mount point; any ordinary directory can.
		mnt=${WORK:?}/binfmt
		mkdir -p "$mnt"
		mount -t binfmt_misc binfmt_misc "$mnt" 2>/dev/null || true
	fi
	[ -e "$mnt/register" ] || die "cannot mount binfmt_misc at $mnt"
	[ -e "$mnt/qemu-aarch64" ] && return 0
	printf ':qemu-aarch64:M:18:\xb7::%s:PF' "$qemu" > "$mnt/register" ||
		die "cannot register qemu-aarch64 in binfmt_misc"
	[ -e "$mnt/qemu-aarch64" ] || die "qemu-aarch64 registration did not appear"
}

# rootfs_bootstrap <dir>: unpack the ArchLinuxARM aarch64 base tarball.
rootfs_bootstrap() {
	local R=$1 url=${ALARM_URL:-$ALARM_MIRROR/os/ArchLinuxARM-aarch64-latest.tar.gz}
	local curl=(curl -fL --retry 3 --connect-timeout 30)
	[ "${PACMAN_INSECURE:-0}" = 1 ] && curl+=(-k)
	log "ArchLinuxARM aarch64 into $R"
	if grep -q " $(realpath -m "$R")/" /proc/mounts; then
		die "something is still mounted under $R - unmount it first"
	fi
	if [ -z "${ALARM_TARBALL:-}" ]; then
		mkdir -p "$WORK/cache"
		ALARM_TARBALL=$WORK/cache/$(basename "$url")
		if [ ! -s "$ALARM_TARBALL" ]; then
			"${curl[@]}" -o "$ALARM_TARBALL.part" "$url"
			mv "$ALARM_TARBALL.part" "$ALARM_TARBALL"
		fi
	elif [ ! -s "$ALARM_TARBALL" ]; then
		die "ALARM_TARBALL=$ALARM_TARBALL is missing"
	fi
	tar -tzf "$ALARM_TARBALL" >/dev/null || die "$ALARM_TARBALL is not a gzip tarball"
	rm -rf --one-file-system "$R"
	mkdir -p "$R"
	tar -C "$R" -xpf "$ALARM_TARBALL" --numeric-owner
}

# configure_pacman <dir>: ALARM mirror, no sandbox (chroot/sysfs), no
# CheckSpace (statvfs inside a chroot), curl as the downloader.
configure_pacman() {
	local R=$1 xfer
	xfer='/usr/bin/curl -L -f -o %o %u'
	[ "${PACMAN_INSECURE:-0}" = 1 ] && xfer='/usr/bin/curl -k -L -f -o %o %u'
	printf 'Server = %s/$arch/$repo\n' "$ALARM_MIRROR" > "$R/etc/pacman.d/mirrorlist"
	# The ALARM tarball carries an [aur] section; the ALARM mirrors do not
	# serve it (it is last in the file).
	sed -i '/^\[aur\]/,$d' "$R/etc/pacman.conf"
	rm -f "$R/var/lib/pacman/sync/aur.db"
	sed -i \
		-e 's/^[#[:space:]]*CheckSpace.*/#CheckSpace/' \
		-e 's/^[#[:space:]]*Architecture.*/Architecture = aarch64/' \
		-e '/^[#[:space:]]*XferCommand/d' \
		-e '/^[#[:space:]]*IgnorePkg/d' \
		-e '/^[#[:space:]]*DownloadUser/d' \
		-e '/^[#[:space:]]*DisableSandboxFilesystem/d' \
		-e '/^[#[:space:]]*DisableSandboxSyscalls/d' \
		"$R/etc/pacman.conf"
	sed -i "/^\[options\]/a\\
XferCommand = $xfer\\
DisableSandboxFilesystem\\
DisableSandboxSyscalls\\
IgnorePkg = linux-aarch64" "$R/etc/pacman.conf"
}

# rootfs_install <dir> <device packages.txt>
rootfs_install() {
	local R=$1 devpkgs=$2 pkgs fwpkgs
	log "packages"
	configure_pacman "$R"
	copy_tree "$REPO/image/arch/rootfs" "$R"
	# The ALARM rootfs resolves DNS through systemd-resolved; the build
	# chroot has no systemd running, so use the host's resolver directly.
	rm -f "$R/etc/resolv.conf"
	cp -L /etc/resolv.conf "$R/etc/resolv.conf"

	if ! in_chroot "$R" pacman-key --list-keys >/dev/null 2>&1; then
		log "pacman keyring"
		in_chroot "$R" pacman-key --init
		in_chroot "$R" pacman-key --populate archlinuxarm
	fi

	# The image boots our own kernel from /boot. Drop the stock one first:
	# otherwise the full upgrade downloads it and mkinitcpio builds an
	# initramfs for a kernel that will never be used.
	in_chroot "$R" pacman -Rdd --noconfirm linux-aarch64 || true
	fwpkgs=$(in_chroot "$R" pacman -Qq | grep '^linux-firmware' || true)
	if [ -n "$fwpkgs" ]; then
		# shellcheck disable=SC2086
		in_chroot "$R" pacman -Rdd --noconfirm $fwpkgs || true
	fi

	in_chroot "$R" pacman -Syu --noconfirm --disable-download-timeout

	pkgs=$(cat "$devpkgs" | sed 's/#.*//' | tr -s ' \t\n' ' ')
	# shellcheck disable=SC2086
	in_chroot "$R" pacman -S --needed --noconfirm --disable-download-timeout $pkgs
}

# rootfs_configure <dir>: the settings every Arch phone image shares.
rootfs_configure() {
	local R=$1 g groups=
	log "common configuration"
	if grep -q "^#$IMAGE_LOCALE" "$R/etc/locale.gen"; then
		sed -i "s/^#$IMAGE_LOCALE/$IMAGE_LOCALE/" "$R/etc/locale.gen"
	elif ! grep -q "^$IMAGE_LOCALE" "$R/etc/locale.gen"; then
		echo "$IMAGE_LOCALE UTF-8" >> "$R/etc/locale.gen"
	fi
	in_chroot "$R" locale-gen
	printf 'LANG=%s\n' "$IMAGE_LOCALE" > "$R/etc/locale.conf"
	printf 'KEYMAP=%s\n' "$IMAGE_KEYMAP" > "$R/etc/vconsole.conf"
	ln -sf "/usr/share/zoneinfo/$IMAGE_TIMEZONE" "$R/etc/localtime"
	printf '%s\n' "$IMAGE_HOSTNAME" > "$R/etc/hostname"
	cat > "$R/etc/hosts" <<EOF
127.0.0.1	localhost
127.0.1.1	$IMAGE_HOSTNAME
::1		localhost ip6-localhost ip6-loopback
EOF

	# One user with sudo, root locked. The password was hashed on the host.
	for g in wheel video render audio input; do
		in_chroot "$R" getent group "$g" >/dev/null && groups="$groups${groups:+,}$g"
	done
	in_chroot "$R" useradd -m -s /bin/bash ${groups:+-G "$groups"} "$IMAGE_USER"
	in_chroot "$R" usermod -p "$IMAGE_PASSWORD_HASH" "$IMAGE_USER"
	in_chroot "$R" passwd -l root >/dev/null

	# Arch's sudoers has %wheel commented out; a drop-in is easier to keep.
	install -d -m 755 "$R/etc/sudoers.d"
	printf '%%wheel ALL=(ALL:ALL) ALL\n' > "$R/etc/sudoers.d/10-wheel"
	chmod 440 "$R/etc/sudoers.d/10-wheel"

	# A phone has no keyboard at the login screen: log the user in, like the
	# reference phones do. The password still guards sudo, SSH and the lock.
	install -d -m 755 "$R/etc/gdm"
	cat > "$R/etc/gdm/custom.conf" <<EOF
[daemon]
WaylandEnable=true
AutomaticLoginEnable=true
AutomaticLogin=$IMAGE_USER
DefaultSession=phosh
EOF
	# GDM takes the user's remembered session from AccountsService. Without
	# this the autologin would start GNOME Shell instead of Phosh.
	install -d -m 700 "$R/var/lib/AccountsService/users"
	cat > "$R/var/lib/AccountsService/users/$IMAGE_USER" <<EOF
[User]
Session=phosh
XSession=phosh
SystemAccount=false
EOF
	chmod 600 "$R/var/lib/AccountsService/users/$IMAGE_USER"

	if [ -n "$IMAGE_SSH_KEY" ]; then
		install -d -m 700 "$R/home/$IMAGE_USER/.ssh"
		printf '%s\n' "$IMAGE_SSH_KEY" > "$R/home/$IMAGE_USER/.ssh/authorized_keys"
		chmod 600 "$R/home/$IMAGE_USER/.ssh/authorized_keys"
		in_chroot "$R" chown -R "$IMAGE_USER:$IMAGE_USER" "/home/$IMAGE_USER/.ssh"
		printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\n' \
			> "$R/etc/ssh/sshd_config.d/20-keys-only.conf"
	fi

	in_chroot "$R" systemctl enable systemd-resolved.service systemd-networkd.service \
		NetworkManager.service sshd.service gdm.service grow-rootfs.service
	in_chroot "$R" systemctl set-default graphical.target
	in_chroot "$R" dconf update
}

# rootfs_device <dir> <base dir>... <device configure.sh>
rootfs_device() {
	local R=$1 dirs=("${@:2:$#-2}") script=${!#} d
	log "device layer"
	for d in "${dirs[@]}"; do copy_tree "$d" "$R"; done
	# Ubuntu's initramfs-tools layer and ssh.service drop-in have no meaning
	# on Arch; the mkinitcpio hook and sshd.service drop-in replace them.
	rm -rf "$R/etc/initramfs-tools" "$R/etc/systemd/system/ssh.service.d"
	install -m 755 "$script" "$R/tmp/device-configure.sh"
	in_chroot "$R" env IMAGE_USER="$IMAGE_USER" /bin/bash /tmp/device-configure.sh
	rm -f "$R/tmp/device-configure.sh"
}

# rootfs_finish <dir>: nothing of the build machine and nothing shared
# between images stays behind.
rootfs_finish() {
	local R=$1
	log "clean up"
	in_chroot "$R" pacman -Scc --noconfirm >/dev/null 2>&1 || true
	rm -rf "$R"/var/cache/pacman/pkg/* "$R"/var/lib/pacman/sync/*
	# SSH host keys are made on the phone's first boot, never shared.
	rm -f "$R"/etc/ssh/ssh_host_*
	# A new machine-id on the first boot.
	: > "$R/etc/machine-id"
	rm -f "$R/var/lib/dbus/machine-id" "$R/var/lib/systemd/random-seed"
	rm -rf "$R"/tmp/* "$R"/var/tmp/* "$R"/root/.bash_history "$R"/var/log/*
	find "$R/etc/pacman.d/gnupg" -name 'S.*' -delete 2>/dev/null || true
	rm -f "$R/etc/resolv.conf"
	ln -sf ../run/systemd/resolve/stub-resolv.conf "$R/etc/resolv.conf"
	# A mirror with a broken certificate only worked with curl -k while
	# building; the phone must not use it. Back to the default mirror and
	# to curl without -k.
	if [ "${PACMAN_INSECURE:-0}" = 1 ]; then
		printf 'Server = http://mirror.archlinuxarm.org/$arch/$repo\n' \
			> "$R/etc/pacman.d/mirrorlist"
	fi
	sed -i 's|^XferCommand = /usr/bin/curl -k |XferCommand = /usr/bin/curl |' \
		"$R/etc/pacman.conf"
}

# make_ext4 <dir> <image> <label> [uuid] [extra MiB]
make_ext4() {
	local R=$1 img=$2 label=$3 uuid=${4:-$(cat /proc/sys/kernel/random/uuid)} extra=${5:-1024}
	local used size files
	log "ext4 image $img"
	used=$(du -sxm "$R" | cut -f1)
	files=$(find "$R" -xdev | wc -l)
	size=$(( (used * 120 / 100 + extra + 63) / 64 * 64 ))
	mkdir -p "$(dirname "$img")"
	rm -f "$img"
	mke2fs -q -F -t ext4 -b 4096 -O ^orphan_file,^metadata_csum_seed -m 1 \
		-N $((files * 3 / 2 + 65536)) -L "$label" -U "$uuid" -d "$R" "$img" "${size}M"
	e2fsck -fn "$img" >/dev/null
	echo "$img: ${size} MiB, ${used} MiB used, UUID $uuid"
}

# sparse_image <raw> <sparse>: Android sparse v1.0 with explicit zero-fill
# chunks, so the flashed partition matches the image byte for byte.
sparse_image() {
	python3 - "$1" "$2" <<'PY'
import struct, sys
src, dst = sys.argv[1], sys.argv[2]
BS = 4096
ZERO = bytes(BS)
chunks = []
with open(src, 'rb') as f:
    f.seek(0, 2); size = f.tell(); f.seek(0)
    assert size % BS == 0, 'image size is not a multiple of 4096'
    total = size // BS
    kind = None; start = 0; n = 0
    for i in range(total):
        k = 'Z' if f.read(BS) == ZERO else 'R'
        if k != kind:
            if kind:
                chunks.append((kind, n, start))
            kind, start, n = k, i, 0
        n += 1
    chunks.append((kind, n, start))
with open(src, 'rb') as f, open(dst, 'wb') as out:
    out.write(struct.pack('<IHHHHIIII', 0xed26ff3a, 1, 0, 28, 12, BS, total, len(chunks), 0))
    for kind, n, start in chunks:
        if kind == 'R':
            out.write(struct.pack('<HHII', 0xCAC1, 0, n, 12 + n * BS))
            f.seek(start * BS)
            left = n * BS
            while left:
                buf = f.read(min(left, 8 << 20)); out.write(buf); left -= len(buf)
        else:
            out.write(struct.pack('<HHII', 0xCAC2, 0, n, 16))
            out.write(struct.pack('<I', 0))
print('%s: %d blocks, %d chunks' % (dst, total, len(chunks)))
PY
}

# checksums <dir>
checksums() {
	(cd "$1" && find . -maxdepth 1 -type f ! -name SHA256SUMS -printf "%f\0" | sort -z | xargs -0 sha256sum -- > SHA256SUMS && cat SHA256SUMS)
}
