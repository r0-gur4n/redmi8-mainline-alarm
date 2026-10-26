# Arch Linux ARM with Phosh

The repository builds two complete userlands for the Redmi 8 from the same
kernel, device tree, drivers, lk2nd and initramfs design:

| | Ubuntu (default) | Arch Linux ARM (this page) |
|---|---|---|
| build script | `image/build-image.sh` | `image/arch/build-image.sh` |
| userland source | Ubuntu ports debootstrap | ArchLinuxARM aarch64 tarball + pacman |
| desktop | GNOME Shell | Phosh on Phoc |
| initramfs | initramfs-tools | mkinitcpio (`device/arch/base/etc/initcpio`) |
| login manager | GDM, autologin | GDM, autologin into the `phosh` session |
| package source | Ubuntu archive | `mirror.archlinuxarm.org` |

Everything below the userland is identical: the kernel is still
`7.1.3-msm89x7-olive-r7`, lk2nd still boots `extlinux.conf` from userdata p1,
the root filesystem still lives in p2 of the disk image on `userdata`, and the
USB rescue shell and boot counter work the same way.

## Build host

On Arch Linux (x86_64; an aarch64 host needs no qemu):

```bash
sudo pacman -S --needed base-devel clang lld llvm bc bison flex openssl \
    libelf zstd python e2fsprogs dosfstools util-linux curl \
    qemu-user-static arm-none-eabi-gcc arm-none-eabi-binutils \
    dtc python-libfdt
```

`qemu-user-static` is only needed when the build host is not aarch64; it
provides `/usr/bin/qemu-aarch64-static`.

## Build

```bash
git clone https://github.com/SheroAbi/redmi8-mainline-linux.git
cd redmi8-mainline-linux

# 1. kernel, modules and the three own drivers (as your normal user)
scripts/build/build-kernel.sh

# 2. Arch Linux ARM, Phosh, initramfs, boot partition and lk2nd
sudo IMAGE_USER=arch image/arch/build-image.sh
```

The build asks for the password of `IMAGE_USER` if `IMAGE_PASSWORD` is not
set. Other settings are the same as for the Ubuntu image (`IMAGE_HOSTNAME`,
`IMAGE_TIMEZONE`, `IMAGE_LOCALE`, `IMAGE_KEYMAP`, `SSH_PUBKEY`); see
`image/arch/lib.sh`.

Output:

```text
dist/image/dtbo.img       minimal DTBO for the dtbo partition
dist/image/userdata.img   sparse disk image for the userdata partition
dist/image/lk2nd.img      second-stage bootloader for the boot partition
dist/image/SHA256SUMS
```

Flash exactly as for the Ubuntu image:

```bash
python3 scripts/flash/flash.py                   # check only
python3 scripts/flash/flash.py --flash --reboot  # dtbo, userdata and boot
```

## Environment

| Variable | Meaning |
|---|---|
| `ALARM_MIRROR` | mirror base URL, default `http://mirror.archlinuxarm.org` |
| `ALARM_TARBALL` | use a downloaded `ArchLinuxARM-aarch64-latest.tar.gz` instead of downloading one |
| `PACMAN_INSECURE` | `1` makes pacman's curl use `-k` during the build (mirror with a broken certificate); the image itself keeps `curl` without `-k` and the default `http://mirror.archlinuxarm.org` mirror |
| `KERNEL_DIR` | staged kernel, default `~/redmi8-build/kernel` |
| `WORK` | scratch directory, default `/var/tmp/redmi8-image-arch` |

The ALARM tarball is cached in `$WORK/cache`. The build removes the stock
`linux-aarch64` package and the generic `linux-firmware` split packages; only
`linux-firmware-qcom` is installed (with the few split packages it depends on,
such as `linux-firmware-atheros` for the Qualcomm/Atheros Wi-Fi firmware).
The rest of `linux-firmware` is ~1.7 GiB for other machines.

## First boot

GDM logs `IMAGE_USER` in automatically and starts the `phosh` session
(AccountsService `Session=phosh`). Over USB the phone is at `172.16.43.1`:

```bash
ssh arch@172.16.43.1
```

The USB control link is created by the initramfs gadget and is reused by
`olive-net.service`; NetworkManager is told to leave `usb0` alone. Wi-Fi is
configured from Phosh's settings.

## Differences you will notice

- The desktop is **Phosh**, not GNOME Shell. Phosh, Phoc, Squeekboard and
  `phosh-mobile-settings` come from the Arch repositories.
- The image ships **Firefox with mobile defaults** instead of Epiphany, plus
  **GNOME Settings** (`gnome-control-center`) and a basic Phosh app set. See
  [Apps, Firefox and Settings](#apps-firefox-and-settings).
- `sudo` works for the `wheel` group through `/etc/sudoers.d/10-wheel`;
  root is locked, as in the Ubuntu image.
- The initramfs is built by `mkinitcpio` with one hook, `olive`, which does
  what the three initramfs-tools scripts do on Ubuntu: USB rescue gadget,
  userdata loop device, boot counter.

## Apps, Firefox and Settings

The app set is chosen for this phone rather than copied from a desktop
install. It adds GNOME Settings, Firefox and the standard Phosh apps:
Calls, Chatty, Contacts, Calendar, Weather, Maps, Clocks, Calculator, Files
(Nautilus), Console, Text Editor, Image Viewer (Loupe), Document Viewer
(Papers), Archive Manager, Characters, Disks and System Monitor.

Calls and Chatty need the modem, which is not supported yet; they open but
cannot register, place calls or send messages. Maps and Weather work over the
network but use no GPS. Camera and music apps are not installed because the
camera and audio hardware are not up yet (see
[`06-known-issues.md`](06-known-issues.md)).

### Firefox mobile defaults

Firefox's stock launcher runs the absolute path
`/usr/lib/firefox/firefox`, so the image installs a small wrapper at
`/usr/local/bin/firefox` and a desktop entry with the same ID at
`/usr/local/share/applications/firefox.desktop` that runs the wrapper. The
wrapper forces the Wayland backend, enables touch input, and passes a portrait
window size that fits the 720x1520 panel, then execs the real binary. The size
is only the starting point: Phoc's auto-maximize sizes the window for the
current display orientation, and a landscape window fills the 1520x720 screen.

```sh
export MOZ_ENABLE_WAYLAND=1
export MOZ_USE_XINPUT2=1
export GDK_BACKEND=wayland
exec /usr/bin/firefox --width 720 --height 1480 "$@"
```

The defaults in `device/arch/base/usr/lib/firefox/defaults/pref/olive-mobile.js`
adapt the UI to the small, high-DPI screen: touch density, tabs in the
titlebar, no bookmarks toolbar, a blank new-tab page (both classic and
Activity Stream), no search suggestions and no startup animations. Touch
events and APZ pinch/double-tap zoom are enabled.
These are defaults, not locks; they can be overridden in `about:config`.
Firefox keeps its normal desktop user agent, so responsive sites still get the
real viewport width and desktop sites are not forced into a mobile layout.

`/etc/xdg/mimeapps.list` makes Firefox the system-wide handler for `http`,
`https` and HTML. The override keeps Firefox's new-window, private-window and
profile-manager actions.

### Phosh favourites

`device/arch/base/etc/dconf/db/local.d/50-olive-arch` sets
`sm.puri.phosh favorites` (and the GNOME Shell equivalent) to Firefox,
Settings, Files, Console, Text Editor and Calculator; all other apps remain
in **Show All Apps**. The image runs `update-desktop-database` and
`dconf update` in `device/arch/configure.sh`. The favourites are ordinary
dconf values, so the user can change them.

## GPU and Mesa

The Adreno 505 is loaded GPU-only (`separate_gpu_kms=1`), so the panel stays
on the bootloader's `simpledrm` framebuffer. Phoc renders with `msm` on the
Adreno render node and wlroots' DRM backend allocates the scanout buffers on
the `simpledrm` display device. Unlike the Ubuntu image, the Arch image does
**not** export `MESA_LOADER_DRIVER_OVERRIDE=kmsro`: the variable is
session-wide, so it would also force client render nodes to `kmsro`, and GTK
4.24 clients then crash while exporting dmabufs (dumb-buffer allocation on
`simpledrm` is denied for a non-master fd). Clients stay on `msm`;
`device/arch/base/usr/local/bin/olive-gpu` replaces the Ubuntu variant and
writes no override. See
[`04-drivers.md`](04-drivers.md#gpu-adreno-505).

## ALARM's phoc and the layer-shell quirk

ALARM's `phoc` package links the system `wlroots0.20` instead of the patched
wlroots subproject that phoc builds by default. Phoc carries
`0001-Revert-layer-shell-error-on-0-dimension-without-anch.patch` for one
reason: Phosh's `"phosh home"` layer surface is size 0x0 anchored to the
bottom, left and right edges, and stock wlroots rejects that with

```
zwlr_layer_surface_v1: error 1: height 0 requested without setting top and bottom anchors
```

The protocol error closes Phosh's Wayland connection, so `phosh` exits with
status 1 a few seconds after `Phosh ready` and the session ends (GDM then sits
on a blank screen). This is an ALARM packaging bug, not a problem of this
port.

The image therefore applies the same revert to the installed
`/usr/lib/libwlroots-0.20.so`:

* `device/arch/base/usr/local/sbin/olive-wlroots-layer-shell-fix` patches one
  instruction (wlroots0.20 0.20.2-1: `0xbc7a8`, `02 04 00 12` →
  `f0 ff ff 17`, sha256 `5e49d34a…` → `a212a0ca…`) and is called from
  `device/arch/configure.sh` during the image build;
* `/etc/pacman.d/hooks/olive-wlroots-layer-shell.hook` runs it again whenever
  `wlroots0.20` is installed or upgraded (a downgrade is also an `Upgrade`
  transaction), so `pacman -Syu` does not bring the crash back.

The script refuses to touch a library whose checksum it does not know: if
ALARM ships a new `wlroots0.20`, the hook fails with a message instead of
guessing. Re-locate the height check, update the offset and both checksums,
and test Phosh. The proper fix belongs in ALARM's phoc package (build it with
`-Dembed-wlroots=enabled`, as upstream does, or patch `wlroots0.20`).

To confirm the fix on a running phone, this should print a growing list of
surface logs and no error:

```bash
journalctl -b _COMM=phosh | grep -E 'Phosh ready|height 0'
```

## Touch and the simpledrm output

Touch works in portrait and landscape. The driver and device tree are the same
as on Ubuntu; the extra step is in Phoc, because the Arch image keeps the
panel on the bootloader's `simpledrm` framebuffer (see
[GPU and Mesa](#gpu-and-mesa)).

Phoc's `phoc_output_is_builtin()` recognizes the output-name prefixes `LVDS-`,
`eDP-`, `DSI-` and `DPI-`. The `simpledrm` output is called `Unknown-1`, so
Phoc finds no builtin output. Two things then go wrong:

* `seat_set_device_output_mappings()` maps a touchscreen only to a builtin
  output, so the Ilitek touch device is left unmapped;
* wlroots applies an output transform to a touch device only when the device
  has a mapped output.

Phosh rotates the output with the accelerometer, but the touch coordinates stay
in the panel's portrait frame, so in landscape the touch no longer follows the
display. Phoc also prints `Touch event ignored since output 'Unknown-1' is
disabled` while the output is off.

The image therefore patches `/usr/bin/phoc` (0.57.0-2, ALARM aarch64):

* `device/arch/base/usr/local/sbin/olive-phoc-simpledrm-output-fix` rewrites the
  inline `eDP-` prefix in `phoc_output_is_builtin()` to `Unkn`
  (`0x4e234`: `a0 8c 88 52 00 aa a5 72` → `a0 ca 8d 52 60 cd ad 72`,
  sha256 `26968002…` → `5c2f2bbe…`); `Unknown-1` is then treated as builtin,
  and its touch device is mapped and rotated with the output. It is also
  called from `device/arch/configure.sh`;
* `/etc/pacman.d/hooks/olive-phoc-simpledrm-output.hook` re-applies the patch
  after `phoc` is installed or upgraded (a downgrade is an `Upgrade`
  transaction).

The `eDP-` branch is no longer recognized as builtin; this phone has no eDP
output, and the `LVDS-`, `DSI-` and `DPI-` branches are unchanged. Because
Phoc now treats the simpledrm output as builtin, it looks for GMobile panel
data for it and logs

```
No panel found for compatibles
gm_display_panel_get_name: assertion 'GM_IS_DISPLAY_PANEL (self)' failed
```

There is no panel description for this device tree, so no cutout is created.
The messages are benign; the session continues and the output is correct.

As with the wlroots patch, the script refuses to touch a binary whose checksum
it does not know. If ALARM updates `phoc`, re-locate the prefix instructions in
the new binary, update the offset and both checksums, and verify that touch
follows the output after rotation. The proper fix belongs in Phoc: recognize
`Unknown-`/`simpledrm` (or use the connector type) in addition to the
panel-name prefixes.

The mapping can be seen with `G_MESSAGES_DEBUG=phoc-seat` in Phoc's
environment:

```
Mapping touch device Ilitek ILI9881H TDDI to Unknown-1
```

A rotation test with the 720x1520 output at transform 90 (scale 1.742188,
logical 872.46x413.27) delivered an injected touch at physical `(100,100)` to
a full-output client at `(814.633,57.359)`, and `(700,20)` at
`(860.527,401.527)`, matching the transformed output.

## Rootless build (optional)

The build normally needs root because it creates a chroot, mounts proc/sys/dev
and writes ext4 images. On a machine without root you can run it inside a
user namespace if `/etc/subuid` and `/etc/subgid` are configured and
`binfmt_misc` can be mounted:

```bash
unshare --user --map-users=0:$(id -u):1 --map-users=1:100000:65535 \
        --map-groups=0:$(id -g):1 --map-groups=1:100000:65535 \
        --mount --pid --fork --mount-proc \
  bash -c 'mount -t binfmt_misc binfmt_misc /tmp/binfmt 2>/dev/null || true;
           exec image/arch/build-image.sh'
```

The script mounts `binfmt_misc` itself; point `BINFMT_DIR` at a writable
directory if `/proc/sys/fs/binfmt_misc` cannot be mounted in the namespace.
