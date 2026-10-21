#!/bin/sh
# Undo install.sh: fprintd goes back to the distro libfprint.
set -eu

sudo rm -f /etc/systemd/system/fprintd.service.d/sigfm.conf
sudo rmdir /etc/systemd/system/fprintd.service.d 2>/dev/null || true
sudo rm -rf /usr/local/lib/libfprint-sigfm
sudo rm -f /etc/modprobe.d/spidev-fingerprint.conf
sudo update-initramfs -u
sudo systemctl daemon-reload
sudo systemctl stop fprintd

echo "Reverted. SIGFM prints cannot be read by the stock library: run 'fprintd-delete \$USER' and enroll again."
echo "spidev bufsiz returns to 4096 after reboot."
