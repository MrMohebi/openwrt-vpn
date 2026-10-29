# OpenWrt VPN

An easy command to remember for running a **WireGuard server on OpenWrt**:

```sh
vpn add phone
vpn help
```

Create a profile for each device, scan its QR code in WireGuard, and connect
back to your home network. Use `full` mode when you also want IPv4 internet
traffic to leave through your home connection.

This configures an incoming VPN server. It does not connect your router to a
commercial VPN provider.

## Requirements

- An OpenWrt router with root SSH access and enough flash space for WireGuard
  and `qrencode`.
- OpenWrt 24.10 with `opkg`, or 25.12 with `apk`. The installer detects the
  package manager. Older releases and development snapshots are not tested.
- An existing LAN firewall zone and WAN firewall zone, normally `lan` and `wan`.
- A public IPv4 address or DNS hostname that reaches your router. If another
  router sits upstream, forward your chosen **UDP** port to OpenWrt's WAN IP.
  Carrier-grade NAT requires an upstream connectivity solution; this script
  cannot create a reachable public address for you.
- WireGuard on the phone, tablet, or computer that will connect.

## Install

Run on the **OpenWrt router**, after connecting with `ssh root@YOUR_ROUTER`:

```sh
wget -O /tmp/install-vpn.sh \
  https://raw.githubusercontent.com/MrMohebi/openwrt-vpn/v1.0.0/install.sh
sh /tmp/install-vpn.sh
```

You can inspect `/tmp/install-vpn.sh` before running it. It downloads the
matching `v1.0.0` command over HTTPS, checks its shell syntax and version, and
installs it as `/usr/bin/vpn`. It installs `kmod-wireguard`, `wireguard-tools`,
and `qrencode` using your router's configured OpenWrt package feeds. It does
not perform a blanket package upgrade.

Installation does not change network or firewall configuration. An existing
`/usr/bin/vpn` is backed up under `/root/vpn-backups/install-*/` before replacement.
Other commands, including an existing `wg-client`, are left in place.

If all dependencies are already present:

```sh
sh /tmp/install-vpn.sh --skip-packages
```

### Install from a checkout

Download or clone this repository, transfer it to the router, and run:

```sh
sh /path/to/openwrt-vpn/install.sh --from /path/to/openwrt-vpn
```

Add `--skip-packages` for an offline install when dependencies are already
installed. Offline installation cannot supply missing kernel modules.

If a kernel dependency cannot be installed, check that your package feeds match
the exact OpenWrt firmware build. Do not force mismatched kernel packages.

## Configure the server

Replace `vpn.example.com` with your public IPv4 address or dynamic DNS hostname.
Replace `192.168.1.0/24` with your actual home LAN network.

First preview the settings:

```sh
vpn setup --endpoint vpn.example.com --lan 192.168.1.0/24 --dry-run
```

Then apply them:

```sh
vpn setup --endpoint vpn.example.com --lan 192.168.1.0/24
```

The separate configuration script offers the same interface from a checkout:

```sh
sh configure.sh --endpoint vpn.example.com --lan 192.168.1.0/24
```

Default settings:

| Setting | Default |
| --- | --- |
| WireGuard interface | `wg0` |
| UDP port | `51820` |
| VPN subnet | `10.7.0.0/24` |
| Router VPN address / client DNS | `10.7.0.1` |
| Client address pool | `10.7.0.2` through `10.7.0.254` |
| Trusted LAN firewall zone | `lan` |
| Internet firewall zone | `wan` |

For a custom port and subnet:

```sh
vpn setup --endpoint vpn.example.com --lan 192.168.50.0/24 \
  --port 41000 --subnet 10.44.0 --interface wg_home
```

Pass `--lan-zone HOME` or `--wan-zone INTERNET` if your firewall zones have
different names. This version supports one managed server, an RFC1918 IPv4
`/24` VPN subnet, and an IPv4/DNS endpoint. IPv6 endpoint literals are unsupported.
Choose a VPN subnet that does not overlap any local, upstream, or remote network.
The script detects overlap with the supplied LAN and configured CIDR addresses;
it cannot discover every network used by a remote device or upstream router.

### What setup changes

- Generates the server private key locally and creates a new UCI WireGuard
  interface. Existing interfaces and keys are not overwritten.
- Adds that interface to your selected **trusted LAN firewall zone**. VPN
  devices can reach router services and LAN devices; this is not guest isolation.
- Adds an IPv4 WAN input rule for the selected UDP port.
- Enables WAN masquerading and ensures LAN-to-WAN forwarding, so full-mode
  profiles can use home internet. These settings also apply to the selected
  LAN/WAN zones generally.
- Saves manager settings in `/etc/config/vpn`; server/peer settings live in
  `/etc/config/network`, and firewall changes in `/etc/config/firewall`.
- Reloads network configuration and the firewall, then starts the new interface.

Setup refuses an existing target interface, an existing manager configuration,
conflicting managed firewall section names, and pending UCI changes in packages
it would commit. It does not adopt/import an existing WireGuard server or its
profiles. For an existing server, keep its current manager, migrate manually,
or choose a new interface **and a nonoverlapping subnet** for this tool.

Setup and later mutations save private configuration backups in
`/root/vpn-backups/change-*/`. Failed changes restore their configuration files
and attempt to reload the previous runtime configuration. Check the reported
error and service state if a reload fails; a file restore cannot guarantee
recovery from every network/service failure.

## Create and connect a device

### Phone or tablet

On the router:

```sh
vpn add phone
```

Open the WireGuard app, choose **Add tunnel → Scan QR code**, and scan the QR
displayed in your terminal. Name the tunnel and turn it on.

To display the QR again:

```sh
vpn show phone
```

For IPv4 internet traffic through home, create the device in `full` mode:

```sh
vpn add travel-phone full
```

Use a separate name/profile for each device. Names may contain letters, numbers,
underscores, and hyphens, up to 40 characters. Names such as `phone-a` and
`phone_a` identify separate devices.

### Laptop or desktop

On the router:

```sh
vpn add laptop full
```

Then run on **your computer**, outside the router's SSH session:

```sh
umask 077
ssh -T root@YOUR_ROUTER 'vpn export laptop' > laptop.conf
```

Replace `YOUR_ROUTER` with its reachable address. Import `laptop.conf` into the
WireGuard client and activate it. QR codes and profile files contain private
keys and must be kept private. Do not post them in issues or commit them to Git.

### Access modes

| Mode | Routes through the tunnel | DNS |
| --- | --- | --- |
| `lan` (default) | VPN subnet and configured home LAN | Home router's VPN IP |
| `full` | All IPv4 destinations (`0.0.0.0/0`) | Home router's VPN IP |

`lan` leaves other internet routes on the device's normal connection, though
DNS queries use home. `full` routes **IPv4 only**; IPv6 is unchanged and may use
the device's normal connection. This tool does not implement an IPv6 tunnel or
a kill switch. If you need all traffic tunneled, manage IPv6 separately.

The mode is chosen when creating a profile. To change it, revoke the old profile,
create a new one with the desired mode, and import it again. Revocation changes
the keys; the old profile will no longer work.

## Everyday commands

| Command | Purpose |
| --- | --- |
| `vpn help` / `vpn --help` / `vpn` | Instructions and examples |
| `vpn add NAME [lan\|full]` | Create a profile and display its QR |
| `vpn show NAME` | Display the saved QR |
| `vpn export NAME` | Print the importable `.conf` profile |
| `vpn list` | List saved names, addresses, and modes |
| `vpn status` | Show live WireGuard handshakes and transfer counters |
| `vpn endpoint HOST` | Change the endpoint in saved profiles |
| `vpn remove NAME` | Revoke a managed peer and delete its active saved profile |
| `vpn version` | Print the installed version |

Adding or removing a client briefly restarts the managed WireGuard interface,
disconnecting active VPN clients. Run those commands from LAN SSH when possible.
Normal LAN/WAN interface restarts are not required for client changes.

Private client profiles are stored as `/etc/wireguard/clients/NAME.conf` with
mode `600` in a private directory. Backups can retain old profiles and keys
after revocation; protect and manage the backup directory accordingly. Revoked
keys cannot connect unless the old server configuration is restored.

### Changed public address

Prefer a dynamic DNS hostname if your public address changes frequently.
To update the endpoint:

```sh
vpn endpoint new-vpn.example.com
```

This updates the manager configuration and all profiles saved on the router.
**Re-import the profiles on devices**, or edit their Endpoint setting yourself;
the router cannot update a profile already imported into a client app. This
command keeps the existing UDP port and keys.

## Test the connection

1. Put a configured phone on mobile data, with Wi-Fi disabled.
2. Activate its WireGuard tunnel and try reaching a home LAN device or router.
3. Run `vpn status` on the router. A recent handshake and increasing transfer
   counters show that the client exchanged traffic with this server.
4. For `full` mode, check the client's **IPv4** public address and DNS resolution;
   IPv4 should leave through the home connection.

Listening on a UDP port or successfully creating a profile does not prove that
the server is reachable from outside your network.

### No handshake

- Confirm the device's tunnel is active and generate traffic to a tunneled IP.
- Check `vpn status`, `logread | tail -n 80`, and the profile's Endpoint.
- Check that DNS resolves your public hostname to the correct public IPv4.
- If OpenWrt has a private WAN address, forward the configured **UDP** port
  through every upstream NAT/router to OpenWrt's WAN address.
- If the ISP uses carrier-grade NAT, ordinary upstream port forwarding may be
  insufficient. Obtain reachable addressing or arrange a separate relay/tunnel.
- Check that the remote network does not use the same subnet as your home LAN.

### Handshake works, but LAN or internet does not

- Verify the profile's mode, client routes, and local device firewall.
- Verify the selected LAN zone accepts input/forwarding as expected. Custom
  restrictive firewall policies may need additional rules.
- For full mode, verify WAN connectivity, masquerading, and LAN-to-WAN forwarding.
- DNS uses the router's VPN address. Make sure your DNS service listens on that
  address and allows requests from VPN clients.

## Backups, upgrade, and removal

The installer registers `/usr/bin/vpn`, `/etc/config/vpn`, and `/etc/wireguard/`
in `/etc/sysupgrade.conf`. Standard OpenWrt configuration backups already cover
network/firewall configuration. Keep sysupgrade backups private: they contain
server and client keys. Packages/kernel modules must still be included or
reinstalled for the new firmware. Check their presence after a firmware upgrade.

To update this tool, download the installer from the desired release tag and
run it. Reinstallation preserves server settings and profiles and backs up the
old command. Do not run setup again on an already configured server.

Each change prints its backup directory. To restore a configuration, inspect
that directory, copy the relevant `network`, `firewall`, and/or `vpn` files back
to `/etc/config/`, and reload the affected services from a LAN maintenance
session. A `vpn.missing` marker means that package did not exist before the
change. Restoring old network configuration can reauthorize previously revoked
peers. Endpoint-change backups also contain a `profiles/` directory, and removal
backups contain the removed client's profile. Preserve matching keys and files.

Removing `/usr/bin/vpn` removes only the manager. The configured WireGuard
interface, firewall rules, keys, and profiles remain until you remove them via
LuCI/UCI or restore the pre-setup configuration. Remove the corresponding
entries from `/etc/sysupgrade.conf` if you no longer want them backed up.

## Development and verification

See [tests/README.md](tests/README.md). CI runs ShellCheck and integration tests
inside disposable OpenWrt 24.10 and 25.12 rootfs containers. Tests use actual UCI
storage, WireGuard key generation, and QR encoding; network service actions and
kernel interface status are simulated. A real external client is required to
verify packet flow and reachability. No keys, credentials, or personal endpoint
addresses are included in this repository.

References: [OpenWrt WireGuard server guide](https://openwrt.org/docs/guide-user/services/vpn/wireguard/server),
[OpenWrt package management](https://openwrt.org/docs/guide-user/additional-software/managing_packages),
and [WireGuard clients](https://www.wireguard.com/install/).

## License

[MIT](LICENSE).
