# OpenWrt VPN

An easy command to remember for running a **WireGuard server on OpenWrt**:

```sh
vpn add phone
vpn help
```

Create a profile for each device, scan its QR code in WireGuard, and connect
back to your home network. Use `full` mode when you also want IPv4 internet
traffic to leave through your home connection.

Keep one simple default network, or add named networks with their own custom
subnets and client IP pools:

```sh
vpn add phone
vpn network add work --cidr 10.20.0.0/24 --pool 10.20.0.50-10.20.0.200
vpn add laptop full --network work
```

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
  https://raw.githubusercontent.com/MrMohebi/openwrt-vpn/v1.1.0/install.sh
sh /tmp/install-vpn.sh
```

You can inspect `/tmp/install-vpn.sh` before running it. It downloads the
matching `v1.1.0` command over HTTPS, checks its shell syntax and version, and
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
  --port 41000 --cidr 10.44.0.0/24 --interface wg_home
```

Pass `--lan-zone HOME` or `--wan-zone INTERNET` if your firewall zones have
different names. Each network uses an RFC1918 private IPv4 subnet with enough
space for a router and at least one client (`/30` or larger). IPv4/DNS endpoints
are supported; IPv6 endpoint literals are unsupported. The legacy
`--subnet 10.44.0` shorthand still means `--cidr 10.44.0.0/24`.
Choose a VPN subnet that does not overlap any local, upstream, or remote network.
The script detects overlap with the supplied LAN, other configured interface
CIDRs, and static interface addresses with netmasks;
it cannot discover every network used by a remote device or upstream router.

## Custom IP ranges and multiple networks

`--cidr` defines the entire network; `--pool` optionally limits the addresses
that can be assigned to clients. They serve different purposes:

```sh
vpn network add work --cidr 10.20.0.0/24 \
  --pool 10.20.0.50-10.20.0.200
```

For this example:

| Setting | Address/range |
| --- | --- |
| Network | `10.20.0.0/24` |
| Router address and client DNS | `10.20.0.1` |
| Automatic client addresses | `10.20.0.50` through `10.20.0.200`, inclusive |
| Reserved | Network address, router address, broadcast address |

The router always uses the first usable address. With no `--pool`, clients can
use every remaining usable address, starting at the second usable address.
Noncanonical CIDRs are normalized and shown in the setup plan; add `--dry-run`
to preview the exact subnet, router address, pool, port, and interface.

### Keep the default simple

The original commands continue to use the **default** network:

```sh
vpn setup --endpoint vpn.example.com --lan 192.168.1.0/24
vpn add phone
vpn add laptop full
vpn list
```

To customize the default during its initial setup:

```sh
vpn setup --endpoint vpn.example.com --lan 192.168.1.0/24 \
  --cidr 10.10.0.0/24 --pool 10.10.0.100-10.10.0.200
```

Already configured networks are never silently renumbered. To move devices to
a different subnet or pool, create a new named network and import new client
profiles. `vpn setup` does not edit an existing default network.

### Add more networks

```sh
vpn network add work --cidr 10.20.0.0/24
vpn network add lab --cidr 10.30.0.0/23 --pool 10.30.0.50-10.30.1.200
vpn network list
vpn network show lab
```

First configure the default network. New networks inherit its endpoint, home
LAN, and firewall zone names. Each new network gets an independent server key,
a free interface name (`wg_vpn1`, `wg_vpn2`, ...), and an available configured
UDP port, starting above the default's port. Ports used by configured interfaces
are skipped; unrelated UDP services are not automatically detected. Override
settings with the same options supported by `vpn setup`:

```sh
vpn network add office --cidr 10.50.0.0/24 \
  --port 51830 --interface wg_office --endpoint office-vpn.example.com
```

If another router is upstream, **forward each network's UDP port** to OpenWrt.
Check `vpn network list` for the actual ports. Additional networks have separate
addresses and WireGuard interfaces; **they share the trusted LAN access policy**
by default. This does not isolate work, lab, or other VPN devices from each
other. Configure firewall zones/rules separately when you need isolation.

### Assign clients to a network

```sh
vpn add phone --network work
vpn add laptop full --network work
vpn add camera --network lab --ip 10.30.0.60
vpn show phone --network work
vpn list --network work
vpn status --network work
vpn endpoint new-vpn.example.com --network work
vpn remove phone --network work
```

`-n work` is a short form of `--network work`. Client names are scoped to each
network, so `phone` can exist in both default and work. Every client uses its
selected network's server key, endpoint, port, router/DNS address, and routes.
`--ip` requests a specific unused address **inside that network's client pool**;
automatic allocation skips it. Exhausted pools and overlapping reservations
are rejected, including addresses/ranges on manually configured peers of that
interface. A freed address can be reused after the old profile is revoked.

Export a named network's client from your computer:

```sh
umask 077
ssh -T root@YOUR_ROUTER 'vpn export laptop --network work' > work-laptop.conf
```

Default profiles keep their original path, `/etc/wireguard/clients/NAME.conf`.
Named network profiles use `/etc/wireguard/clients/NETWORK/NAME.conf`.
Endpoint updates and client removals affect only the selected network, and
client changes restart only its WireGuard interface.

### Remove an empty network

Revoke its clients first, then remove it:

```sh
vpn remove laptop --network work
vpn network remove work
```

Removal refuses a network with saved profiles or any remaining peers. It removes
only that named network's interface, manager settings, firewall rules, and LAN
zone membership. The default network is retained. Shared zone settings, such as
WAN masquerading, remain enabled; restore a pre-setup backup if you want the
original zone policy back.

### Upgrade from v1.0

Run the v1.1 installer. Existing `vpn.server` settings, `--subnet` values,
default client filenames, and peer section names are read as the default
network without changing keys or re-exporting profiles. You can then add named
networks. Installing the manager does not import an unrelated custom WireGuard
server or the earlier standalone `wg-client` script's configuration.

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

Setup refuses an existing target interface, an existing target network,
conflicting managed firewall section names, and pending UCI changes in packages
it would commit. It does not adopt/import an existing WireGuard server or its
profiles. For an unrelated existing server, keep its current manager, migrate
manually, or choose a new interface **and a nonoverlapping subnet** for this tool.

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
| `vpn network list` | List all networks and their ranges, ports, and interfaces |
| `vpn network show NAME` | Show a network's settings and allocation pool |
| `vpn network add NAME --cidr CIDR [options]` | Create a named network |
| `vpn network remove NAME` | Remove an empty named network |

Add `--network NETWORK` to client, status, list, or endpoint commands to select
a named network. `vpn add` also accepts `--ip ADDRESS` for a fixed client IP.

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

This updates the selected network's manager settings and saved profiles. With
no selector it updates the default network only. Named networks inherit an
endpoint value at creation; later default endpoint changes do not propagate to
them automatically. Use `--network NAME` to update each one as needed.
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
kernel interface status are simulated. Checks cover v1.0 compatibility, custom
CIDRs, pools crossing octet boundaries, fixed IPs, conflicts, pool exhaustion,
and network selection/removal. A real external client is required to
verify packet flow and reachability. No keys, credentials, or personal endpoint
addresses are included in this repository.

References: [OpenWrt WireGuard server guide](https://openwrt.org/docs/guide-user/services/vpn/wireguard/server),
[OpenWrt package management](https://openwrt.org/docs/guide-user/additional-software/managing_packages),
and [WireGuard clients](https://www.wireguard.com/install/).

## License

[MIT](LICENSE).
