#!/bin/bash
# Redmi 8 (Arch): hardware configuration, run inside the image during the
# build (image/arch/build-image.sh). Only what this phone needs to work; the
# optional features are in extras/.
set -euo pipefail

# Firmware from the phone's own Android partitions (Wi-Fi calibration,
# wcnss, ADSP, venus), linked at every boot before udev.
systemctl enable msm-firmware-loader.service

# GPU (msm GPU-only, Mesa msm/kmsro), Wi-Fi without 802.11n TX aggregation,
# the USB control link (systemd-networkd serves DHCP on usb0), and the
# confirmation that resets the initramfs boot counter.
systemctl enable olive-gpu.service olive-wifi-noht.service olive-net.service \
	olive-watch.service olive-autoconfirm.timer systemd-networkd.service

# Suspend never resumes on this port.
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target \
	suspend-then-hibernate.target

# ALARM's phoc links the system wlroots0.20, which lacks the layer-shell
# revert that phoc's own embedded wlroots carries. Without it phosh exits
# right after startup ("height 0 requested without setting top and bottom
# anchors"). The pacman hook in /etc/pacman.d/hooks re-applies the same
# fix when wlroots0.20 changes.
/usr/local/sbin/olive-wlroots-layer-shell-fix

# The panel is driven by the bootloader's simpledrm output "Unknown-1". Phoc
# maps touchscreens only to outputs it considers builtin, so the Ilitek touch
# would stay unmapped and would not follow Phosh's rotation. The pacman hook
# in /etc/pacman.d/hooks re-applies this when phoc changes.
/usr/local/sbin/olive-phoc-simpledrm-output-fix

# Register Firefox, GNOME Settings and the other app launchers, then apply the
# system dconf defaults (Phosh favourites, shared phone settings).
update-desktop-database -q /usr/share/applications
update-desktop-database -q /usr/local/share/applications
dconf update
