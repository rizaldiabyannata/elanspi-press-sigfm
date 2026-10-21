#!/bin/sh
# Build the SIGFM libfprint fork with the elanspi press-mode patch and make fprintd use it.
# Run as your normal user; it calls sudo only for the install steps.
# The distro libfprint package is left untouched (its udev rule still binds the sensor to spidev).
set -eu

FORK=https://github.com/goodix-fp-linux-dev/libfprint.git
COMMIT=07306bbc9256942595e31fb0f407b364ffa24d07
LIBDIR=/usr/local/lib/libfprint-sigfm
HERE=$(cd "$(dirname "$0")/.." && pwd)
WORK=${WORK:-$(mktemp -d)}

echo "==> fetching libfprint SIGFM fork @ $COMMIT into $WORK"
git init -q "$WORK/libfprint"
cd "$WORK/libfprint"
git fetch -q --depth 1 "$FORK" "$COMMIT"
git checkout -q FETCH_HEAD
git apply "$HERE/patches/elanspi-sigfm-press.patch"

echo "==> building (elanspi; aes4000 only pulls in pixman for image scaling)"
meson setup build -Ddrivers=elanspi,aes4000 -Dintrospection=false -Ddoc=false \
  -Dgtk-examples=false -Dudev_rules=disabled -Dudev_hwdb=disabled >/dev/null
ninja -C build >/dev/null

echo "==> installing (sudo)"
sudo install -d "$LIBDIR"
sudo cp -P build/libfprint/libfprint-2.so build/libfprint/libfprint-2.so.2 build/libfprint/libfprint-2.so.2.0.0 "$LIBDIR/"

# one HV frame is ~16.6 KB; the 4096-byte default makes every capture time out
echo 'options spidev bufsiz=32768' | sudo tee /etc/modprobe.d/spidev-fingerprint.conf >/dev/null
sudo update-initramfs -u

sudo mkdir -p /etc/systemd/system/fprintd.service.d
printf '[Service]\nEnvironment=LD_LIBRARY_PATH=%s\n' "$LIBDIR" |
  sudo tee /etc/systemd/system/fprintd.service.d/sigfm.conf >/dev/null
sudo systemctl daemon-reload
sudo systemctl stop fprintd
sudo sh -c 'modprobe -r spidev && modprobe spidev'

echo "spidev bufsiz now: $(cat /sys/module/spidev/parameters/bufsiz) (expected 32768)"
cat <<EOF

Done. Old prints are NBIS-format and will not load; enroll again (press, don't swipe):
  fprintd-delete \$USER
  fprintd-enroll -f right-index-finger
Then test with scripts/test-verify.sh, and optionally: sudo pam-auth-update --enable fprintd
EOF
