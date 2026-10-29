#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu
umask 077
REF=v1.0.0
SOURCE=
SKIP=0
usage() {
    cat <<'EOF'
Usage: sh install.sh [--from CHECKOUT] [--skip-packages]

Install the vpn command on OpenWrt. No network/firewall configuration is changed.
  --from PATH       Install bin/vpn from a downloaded repository checkout
  --skip-packages   Use dependencies already installed on the router
  -h, --help        Show this help

After installation:
  vpn setup --endpoint vpn.example.com --lan 192.168.1.0/24 --dry-run
  vpn setup --endpoint vpn.example.com --lan 192.168.1.0/24
  vpn add phone
  vpn help
EOF
}
while [ "$#" -gt 0 ]; do
    case "$1" in
        --from) [ "$#" -ge 2 ] || { usage >&2; exit 1; }; SOURCE=$2; shift 2;;
        --skip-packages) SKIP=1; shift;;
        -h|--help) usage; exit 0;;
        *) usage >&2; exit 1;;
    esac
done
[ "$(id -u)" = 0 ] || { echo 'Run as root on OpenWrt.' >&2; exit 1; }
[ -f /etc/openwrt_release ] || { echo 'This installer requires OpenWrt.' >&2; exit 1; }
if [ "$SKIP" = 0 ]; then
    if command -v opkg >/dev/null 2>&1; then
        opkg update
        opkg install kmod-wireguard wireguard-tools qrencode
    elif command -v apk >/dev/null 2>&1; then
        apk update
        apk add kmod-wireguard wireguard-tools qrencode
    else echo 'No supported OpenWrt package manager found.' >&2; exit 1; fi
fi
for tool in uci wg ifup ifdown qrencode; do
    command -v "$tool" >/dev/null 2>&1 || { echo "Missing dependency: $tool" >&2; exit 1; }
done
WORK=$(mktemp -d /tmp/install-vpn.XXXXXX)
trap 'rm -rf "$WORK"' 0
trap 'exit 130' INT
trap 'exit 143' HUP TERM
if [ -n "$SOURCE" ]; then cp "$SOURCE/bin/vpn" "$WORK/vpn"
else
    wget -O "$WORK/vpn" "https://raw.githubusercontent.com/MrMohebi/openwrt-vpn/$REF/bin/vpn"
fi
sh -n "$WORK/vpn"
[ "$(sh "$WORK/vpn" version)" = "${REF#v}" ] || { echo 'Downloaded version does not match the installer.' >&2; exit 1; }
mkdir -p /usr/bin
if [ -e /usr/bin/vpn ]; then
    mkdir -p /root/vpn-backups
    backup=$(mktemp -d /root/vpn-backups/install-XXXXXX)
    cp -p /usr/bin/vpn "$backup/vpn"
    echo "Previous command backed up to $backup/vpn"
fi
# Stage on the destination filesystem so the final rename is atomic.
staged=$(mktemp /usr/bin/.vpn-install.XXXXXX)
if ! cp "$WORK/vpn" "$staged" || ! chmod 700 "$staged" || ! mv "$staged" /usr/bin/vpn; then
    rm -f "$staged"
    exit 1
fi
# Preserve program, config, and private profiles in OpenWrt sysupgrade backups.
touch /etc/sysupgrade.conf
for path in /usr/bin/vpn /etc/config/vpn /etc/wireguard/; do
    grep -qxF "$path" /etc/sysupgrade.conf || printf '%s\n' "$path" >> /etc/sysupgrade.conf
done
echo 'Installed. Next: vpn setup --endpoint vpn.example.com --lan 192.168.1.0/24'
echo 'Preview with --dry-run. See all instructions with: vpn help'
