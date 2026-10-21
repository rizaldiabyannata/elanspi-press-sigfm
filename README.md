# elanspi press mode + SIGFM for ELAN eFSA80SC

Makes the ELAN SPI fingerprint reader in some ASUS VivoBooks usable on Linux.
Tested on an **ASUS VivoBook X415FAC**, Ubuntu 26.04, fprintd 1.94.5.

*Ringkasan Bahasa Indonesia ada di bagian bawah.*

## Is this your case?

All of these should match:

```sh
grep -l ELAN7001 /sys/bus/acpi/devices/*/hid     # ACPI ELAN7001 (or ELAN70A1)
ls /dev/spidev*                                   # sensor bound to spidev
fprintd-list $USER                                # "ElanTech Embedded Fingerprint Sensor"
```

and with `G_MESSAGES_DEBUG=all /usr/libexec/fprintd -t` (fprintd stopped first) the log shows
`found sensor ID 14 => [eFSA80SC] (80 x 80)`.

Typical symptoms:

1. `fprintd-enroll` → `enroll-unknown-error`, log says `timed out waiting for image`.
2. After fixing that, enroll works but `fprintd-verify` is always `verify-no-match`
   (`score 0/24` on every comparison), and you keep getting `swipe-too-short`.

## What is wrong

| Problem | Cause | Fix |
|---|---|---|
| `timed out waiting for image` during calibration | One HV frame is 80 × (80×2+48) = 16,640 bytes; the default `spidev.bufsiz` is 4096. Raising the driver timeout does **not** help. | `options spidev bufsiz=32768` |
| Score 0 on every verify | `elanspi` treats every sensor as a swipe sensor and stitches frames. eFSA80SC is an 80×80 **press** sensor (Windows uses it by touch), so stitching near-identical frames produces garbage. | Press mode: average the 3 newest frames of a still finger, no stitching |
| Few minutiae on 80×80 | NBIS/bozorth3 needs a large area | SIGFM keypoint matcher (from the goodix-fp-linux-dev fork), threshold 15 |
| Small patch of finger per press | — | 15 enroll stages instead of 7 |
| Prompts say "swipe" | scan type was only known after calibration | flag the device as press at open |

## Results (one user, one laptop — a small sample)

| Setup | Enrolled finger | Different finger |
|---|---|---|
| Stock libfprint 1.95.1 (NBIS, swipe) | 0/5 | – |
| SIGFM + press, 7 stages, single frame | 4/6 | 0/4 |
| SIGFM + press, 15 stages, single frame | 1/6 | 0/4 |
| SIGFM + press, 15 stages, 3-frame average, threshold 15 | 5/6 | 0/4 |
| **same + two-phase enroll (centre, then edges)** | **3/3 normal, 5/6 deliberately misplaced** | **0/4** |

Different fingers scored 0 in every comparison. ~50 attempts is not a security evaluation:
treat the fingerprint as a convenience and keep your password.

## How to enroll

The sensor sees only an ~80×80 patch of the finger, so a verify press can only match a part of the
finger that was recorded at enroll. Cover the finger like Windows Hello's two-phase enroll does:

- presses **1–8: centre** of the fingertip, shifting slightly each time;
- presses **9–15: edges** — tip, base, left, right, diagonals — each still overlapping some centre.

Press, hold ~0.5 s, lift. Each `enroll-stage-passed` line is one accepted press.

Fusing the presses into one larger "map" template was tried and dropped: in two test rounds it never
decided a match (every success came from an individual press), because presses either overlapped
strongly (44–99 RANSAC inliers) or not at all (0–4), and the individual templates already cover the
strong overlaps.

## Install

Build dependencies (Ubuntu/Debian names):

```sh
sudo apt install git meson ninja-build build-essential pkg-config \
  libglib2.0-dev libgusb-dev libgudev-1.0-dev libudev-dev libpixman-1-dev libopencv-dev
```

Keep your distro's `libfprint` and `fprintd` installed: its udev rule binds ELAN7001 to spidev.

```sh
sh scripts/install.sh
fprintd-delete $USER                      # old NBIS prints cannot be read by SIGFM
fprintd-enroll -f right-index-finger      # PRESS, don't swipe: 8x centre, 7x edges (see "How to enroll")
sh scripts/test-verify.sh                 # counts accepted/rejected attempts
sudo pam-auth-update --enable fprintd     # optional: sudo / login with fingerprint
```

`install.sh` builds the SIGFM fork at a pinned commit with `patches/elanspi-sigfm-press.patch`,
copies the library to `/usr/local/lib/libfprint-sigfm`, sets `spidev bufsiz=32768`, and adds a
systemd drop-in so **only fprintd** loads it (`LD_LIBRARY_PATH`). The distro library is not replaced,
so `apt upgrade` will not undo it.

**Don't touch the sensor for ~1 second when enroll/verify starts:** the driver calibrates then, and a
finger on the sensor ruins the background frame (every later frame reads flat and nothing is detected).

Undo: `sh scripts/uninstall.sh`, then delete and re-enroll your prints.

## Other touchpad PIDs

The patch adds only touchpad `04F3:3128`. Find yours with
`cat /sys/bus/i2c/devices/i2c-ELAN*/*/modalias` (`...v000004F3p0000XXXX`) and add a line to
`elanspi_id_table` in `libfprint/drivers/elanspi.h` of the fork, keeping `ELANSPI_PRESS_SENSOR`:

```c
{.udev_types = ELANSPI_UDEV_TYPES, .spi_acpi_id = "ELAN7001", .hid_id = {.vid = ELANSPI_TP_VID, .pid = 0xXXXX}, .driver_data = ELANSPI_NO_ROTATE | ELANSPI_PRESS_SENSOR},
```

Press mode itself switches on for any sensor detected as ID 14 (eFSA80SC). Other sensor IDs keep
the original swipe behaviour.

## Known issues

- Based on the 2023 SIGFM fork (`07306bb`). It prints `CRITICAL g_object_unref` when an enroll
  finishes; enroll still completes and verifies.
- Threshold 15 and 3-frame averaging were tuned on one machine. Your scores are in the fprintd debug
  log (`sigfm score N/15`).

## Why not port the Windows driver?

The ASUS package `Fingerprint_WBF_USB_DCH_ELAN_Z_V3.5.11401.10301` is for the **USB** Match-on-Chip
sensor `04F3:0C90` (build path `Branch_ASUS_MOC_CB`): matching runs inside the sensor firmware, so it
holds no host-side algorithm for this SPI sensor. No ELAN/ASUS files are included in this repo.

## Credits

- [libfprint](https://gitlab.freedesktop.org/libfprint/libfprint) and the `elanspi` driver.
- [goodix-fp-linux-dev/libfprint](https://github.com/goodix-fp-linux-dev/libfprint) — SIGFM.
- libfprint issues [#867](https://gitlab.freedesktop.org/libfprint/libfprint/-/issues/867) (spidev
  bufsiz + SIGFM on eFSA80SC), [#877](https://gitlab.freedesktop.org/libfprint/libfprint/-/issues/877),
  [#514](https://gitlab.freedesktop.org/libfprint/libfprint/-/issues/514).

License: LGPL-2.1-or-later, same as libfprint.

---

## Ringkasan (Bahasa Indonesia)

Untuk laptop ASUS dengan sensor sidik jari ELAN SPI (`ELAN7001`, terdeteksi sebagai eFSA80SC 80×80).
Ada tiga masalah: buffer `spidev` terlalu kecil (error `timed out waiting for image`), driver
memperlakukan sensor **tekan** sebagai sensor **usap** (skor selalu 0), dan matcher NBIS tidak cocok
untuk area kecil. Repo ini memperbaiki ketiganya: buffer 32 KB, mode tekan, dan matcher SIGFM.
Hasil uji: tempelan normal 3/3, sengaja meleset 5/6, jari lain 0/4. Pasang dengan
`sh scripts/install.sh`, lalu enroll ulang dengan cara **menempel**, bukan mengusap: 8 kali di tengah,
lalu 7 kali di tepi (ujung, pangkal, kiri, kanan, serong), dan setiap tempelan tepi tetap menutupi
sebagian tengah. Jangan sentuh sensor sekitar 1 detik saat enroll/verify dimulai, karena saat itu
sensor sedang kalibrasi.
