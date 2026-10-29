# Tests

`integration.sh` must run in a disposable OpenWrt container. It intentionally
replaces that container's network/firewall configuration and service scripts.
Never run it on a router.

```sh
docker run --rm --platform linux/x86_64 --user root \
  -e VPN_TEST_CONTAINER=1 -v "$PWD:/src:ro" \
  --entrypoint /bin/sh ghcr.io/openwrt/rootfs:x86_64-24.10.8 -c \
  'mkdir -p /var/lock && opkg update && opkg install wireguard-tools qrencode && sh /src/tests/integration.sh'
```

On Apple Silicon use `aarch64_generic-24.10.8` and
`--platform linux/aarch64_generic`. OpenWrt images use their target architecture
names in OCI metadata, so the explicit platform is needed. For 25.12 use a matching rootfs
tag and replace the package commands with `apk update && apk add wireguard-tools
qrencode`.

These tests use the actual UCI parser/storage, WireGuard key generation, and QR
encoder. Only kernel interface status and network/firewall service actions are
simulated. They verify installation, setup, rollback, address allocation,
profile export, revocation, endpoint updates, and rejection of unsafe input.
They also cover legacy v1.0 settings/profiles, separate named networks and keys,
automatic ports, custom CIDRs and allocation pools, fixed IPs, pool exhaustion,
overlap checks, scoped updates, and removal without affecting default profiles.
They do not prove internet reachability, DNS resolution, firewall packet flow,
or a successful WireGuard handshake. Test those from an external device.

Static checks:

```sh
shellcheck bin/vpn install.sh configure.sh tests/integration.sh
sh -n bin/vpn
sh -n install.sh
sh -n configure.sh
```
