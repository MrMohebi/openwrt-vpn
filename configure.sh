#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu
SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
if [ -f "$SCRIPT_DIR/bin/vpn" ]; then
    exec sh "$SCRIPT_DIR/bin/vpn" setup "$@"
fi
exec /usr/bin/vpn setup "$@"
