# Arch Linux on the Xiaomi Redmi 8 (experimental)

**WARNING:** Both the original project and the fork were made with assist of AI and come without any warranty. Flashing can go wrong and brick your phone, so do it at your own risk.<br><br>

---
## What is this
Native port of [Arch Linux ARM](https://archlinuxarm.org/) with [Phosh](https://phosh.mobi/) GUI for the Xiaomi Redmi 8 (olive). It uses mainline 7.1.3 kernel with some custom drivers and fixes. Based on SheroAbi's [Ubuntu 24.04 port](https://github.com/SheroAbi/redmi8-mainline-linux).<br>
The project is unfinished, and there's still a bunch of files from the original repo. I think you can still build Ubuntu for the phone using just this repo.<br><br>
Demo of working Arch Linux on device:<br>
<img src="https://github.com/r0-gur4n/redmi8-mainline-alarm/blob/main/alarm-demo.png" alt="ALARM demo" width="360" height="760">

---
## What works (or not)
| Feature | State |
|---|---|
| Boot | Works |
| USB Net | Works |
| Rescue | Works |
| Screen | Works |
| Suspend | Broken |
| Touch | Works |
| GPU/3D Accel. | Mostly works |
| Battery | Works |
| Wi-Fi/BT | Works |
| GPS | Broken |
| Sound | Partially works |
| Mic | Broken |
| Camera | Broken |
| Cellular | Broken |
| USB OTG | Broken |
| Fingerprint | Broken |
| Accelerometer | Works |

P.S.: There can be artifacts, possibly related to GPU; Wi-Fi works slower than it could; audio works with artifacts, especially on lower volume, don't know how to fix it yet.<br>
P.P.S. Looks like Vulkan doesn't work, but OpenGL still works.

---
## Building
Read [07-arch.md](https://github.com/r0-gur4n/redmi8-mainline-alarm/blob/main/docs/07-arch.md).<br>
If something goes wrong, please submit an issue. Even though AI has gotten pretty good, it can still make mistakes.

---
## Troubleshooting
| Problem | Fix |
|---|---|
| Xiaomi logo, then back to fastboot / lk2nd | `boot` or `userdata` is wrong: flash again. |
| Boot text, then black, USB network up | Userspace hung. `telnet 169.254.66.1` over the cable for the rescue shell; after 3 unconfirmed boots the initramfs stops there on its own. |
| Desktop, but no touch or brightness | Another panel/backlight variant ([docs/01-hardware.md](docs/01-hardware.md)). Reports from other units are very welcome. |
| Nothing at all | Hold Power button ~15 s (hard reset), then Volume Down + Power buttons to enter fastboot. |
| `flash.py` refuses: battery | Charge above 3.7 V first. |
| No suspend | There's still no suspend. |
| `DRM_IOCTL_MODE_CREATE_DUMB failed: Permission denied` error when trying to open apps | This bug was fixed in Arch Linux port, but it couldn't be applied for Ubuntu |
| There's nothing about my specific problem | Submit an issue |

P.S.: Actually, brightness *could be* fixed when I did troubleshooting on my unit, not sure if it will work on other units though.

---
## Future of the project

Q: Will I continue working on this?
I don't know for sure, it may be abandoned in favor of other projects, due to laziness/lost of interest, due to no Internet access, or any other reason. If I won't help you, you can always fork this project.

---
## Credits

[SheroAbi](https://github.com/SheroAbi) for the original Ubuntu port<br>
[barni2000](https://github.com/barni2000) and other [msm89x7-mainline](https://github.com/msm89x7-mainline) contributors<br>
[DeepSeek AI](https://www.deepseek.com/) for assisting in this project<br>
[Linus Torvalds](https://github.com/torvalds) for the Linux kernel (and Git)

---
## License

GPL-2.0-only for drivers, patches and device trees, see [LICENSE](LICENSE).
Firmware and reference files keep their own terms, listed in
[THIRD-PARTY.md](THIRD-PARTY.md).
