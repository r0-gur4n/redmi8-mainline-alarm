# Firmware

Installed in the image under `/usr/lib/firmware/`; kept here so the port can
be rebuilt without a stock ROM at hand.

| File | Needed by | Source |
|---|---|---|
| `qcom/sdm439/xiaomi/olive/a506_zap.{mdt,b00,b01,b02}` | Adreno 505 (zap shader through TrustZone) | stock `vendor` partition, `/vendor/firmware/a506_zap.*` |
| `ilitek/olive-ili9881h-c3i-0x04.ili` | `ili9881h-tddi-fb` (touch RAM firmware, C3I/Tianma panel) | vendor kernel `C3I_TIANMA_6217_LongH_V0x04.ili` (a text array of hex bytes), converted byte for byte with `convert-touch-firmware.py` |
| `dtbo/dtbo-xiaomi-olive.img` | the stock bootloader, before it starts lk2nd | [barni2000/dtbo-lk2nd](https://github.com/barni2000/dtbo-lk2nd) release `v2025.12.21` |

The DTBO is not part of the root filesystem: it goes to the phone's `dtbo`
partition (the image build copies it to `dist/image/dtbo.img` and
`scripts/flash/flash.py` writes it).

SDM429/SDM439/SDM632 devices such as the Redmi 8 need a *minimal* DTBO. With
the stock overlay the bootloader tries to patch lk2nd's device trees with
references to nodes that no longer exist and refuses to start lk2nd, ending up
in fastboot again. The file here contains only a `qcom,board-id` fixup:
190 bytes, sha256
`1de2f01ec47a9187b34ad24eee7cfcdfa10d47c7af420339040bd2c7adf0d8f3`.

Everything else comes from the phone itself at boot (`msm-firmware-loader`):
Wi-Fi (`wcnss.*`) and its per-unit calibration `WCNSS_qcom_wlan_nv.bin` from
`persist`, ADSP from `modem`, venus from `vendor`.
