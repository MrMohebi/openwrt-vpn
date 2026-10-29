#!/bin/sh
# Integration tests use real OpenWrt UCI, WireGuard key generation and qrencode.
# Only netifd/firewall reloads and kernel interface status are simulated.
set -eu
if [ "${VPN_TEST_CONTAINER:-}" != 1 ] || [ ! -f /.dockerenv ]; then
    echo 'Run only in a disposable OpenWrt Docker container; see tests/README.md.' >&2
    exit 1
fi
SRC=${SRC:-/src}
TEST_DIR=$(mktemp -d /tmp/vpn-tests.XXXXXX)
mkdir "$TEST_DIR/bin"
REAL_WG=$(command -v wg)
export REAL_WG TEST_DIR
cat > "$TEST_DIR/bin/wg" <<'EOF'
#!/bin/sh
case "$1" in
    show) [ -f "$TEST_DIR/up-$2" ] && echo "interface: $2";;
    *) exec "$REAL_WG" "$@";;
esac
EOF
cat > "$TEST_DIR/bin/ifdown" <<'EOF'
#!/bin/sh
echo "down $1" >> "$TEST_DIR/calls"
rm -f "$TEST_DIR/up-$1"
EOF
cat > "$TEST_DIR/bin/ifup" <<'EOF'
#!/bin/sh
[ ! -f "$TEST_DIR/fail-up" ] || exit 1
echo "up $1" >> "$TEST_DIR/calls"
touch "$TEST_DIR/up-$1"
EOF
cat > /etc/init.d/network <<'EOF'
#!/bin/sh
exit 0
EOF
cp /etc/init.d/network /etc/init.d/firewall
chmod +x "$TEST_DIR/bin/"* /etc/init.d/network /etc/init.d/firewall
PATH="$TEST_DIR/bin:$PATH"
export PATH
fail() { echo "FAIL: $*" >&2; exit 1; }
expect_fail() { if "$@" >"$TEST_DIR/output" 2>&1; then fail "unexpected success: $*"; fi; }
snapshot() { uci export network; uci export firewall; }
fixtures() {
    rm -f /etc/config/vpn "$TEST_DIR/"up-* "$TEST_DIR/fail-up" "$TEST_DIR/calls"
    rm -rf /etc/wireguard /tmp/.uci /var/lock/openwrt-vpn
    mkdir -p /etc/config
    cat > /etc/config/network <<'EOF'
config interface 'lan'
 option proto 'static'
 option ipaddr '192.168.1.1'
 option netmask '255.255.255.0'
config interface 'wan'
 option proto 'dhcp'
EOF
    cat > /etc/config/firewall <<'EOF'
config zone
 option name 'lan'
 list network 'lan'
 option input 'ACCEPT'
 option output 'ACCEPT'
 option forward 'ACCEPT'
config zone
 option name 'wan'
 list network 'wan'
 option masq '1'
config forwarding
 option src 'lan'
 option dest 'wan'
EOF
}
setup_server() { vpn setup --endpoint vpn.example.com --lan 192.168.1.0/24 "$@" > "$TEST_DIR/output"; }
fixtures
sh "$SRC/install.sh" --from "$SRC" --skip-packages > "$TEST_DIR/output"
vpn help > "$TEST_DIR/help"
vpn --help > "$TEST_DIR/output"
cmp "$TEST_DIR/help" "$TEST_DIR/output"
[ "$(vpn version)" = 1.1.0 ] || fail version
sh "$SRC/install.sh" --from "$SRC" --skip-packages > "$TEST_DIR/output"
[ "$(grep -cx /usr/bin/vpn /etc/sysupgrade.conf)" = 1 ] || fail 'duplicate sysupgrade entry'
echo 'PASS: offline installer, reinstall, help and version'
snapshot > "$TEST_DIR/before"
setup_server --dry-run
snapshot > "$TEST_DIR/after"
cmp "$TEST_DIR/before" "$TEST_DIR/after"
[ ! -f /etc/config/vpn ] || fail 'dry run wrote config'
expect_fail vpn setup --endpoint example.com --lan 10.7.0.0/24 --dry-run
expect_fail vpn setup --endpoint example.com --lan 192.168.1.0/24 --subnet 8.8.8 --dry-run
expect_fail vpn setup --endpoint example.com --lan 192.168.1.0/24 --port 70000 --dry-run
expect_fail vpn setup --endpoint 'example.com;id' --lan 192.168.1.0/24 --dry-run
echo 'PASS: dry run, subnet overlap, private subnet, port and endpoint validation'
touch "$TEST_DIR/fail-up"
expect_fail vpn setup --endpoint vpn.example.com --lan 192.168.1.0/24
snapshot > "$TEST_DIR/after"
cmp "$TEST_DIR/before" "$TEST_DIR/after"
[ ! -f /etc/config/vpn ] || fail 'failed setup left config'
rm "$TEST_DIR/fail-up"
echo 'PASS: failed setup restores actual UCI configuration'
setup_server
[ "$(uci get network.wg0.proto)" = wireguard ] || fail protocol
[ "$(uci get firewall.wg_vpn_input.dest_port)" = 51820 ] || fail firewall
[ "$(uci get 'firewall.@zone[0].network')" = 'lan wg0' ] || fail 'zone membership'
expect_fail vpn setup --endpoint vpn.example.com --lan 192.168.1.0/24
echo 'PASS: server setup and existing-configuration protection'
vpn add phone-a > "$TEST_DIR/output"
vpn add phone_a full > "$TEST_DIR/output"
[ "$(find /etc/wireguard/clients -type f | wc -l)" -eq 2 ] || fail 'client count'
grep -q '^Address = 10.7.0.2/32$' /etc/wireguard/clients/phone-a.conf || fail 'first address'
grep -q '^Address = 10.7.0.3/32$' /etc/wireguard/clients/phone_a.conf || fail 'second address'
grep -q '^AllowedIPs = 0.0.0.0/0$' /etc/wireguard/clients/phone_a.conf || fail 'full mode'
vpn export phone-a > "$TEST_DIR/export"
cmp "$TEST_DIR/export" /etc/wireguard/clients/phone-a.conf
vpn show phone-a > "$TEST_DIR/qr"
qrencode -t ANSIUTF8 < "$TEST_DIR/export" > "$TEST_DIR/expected-qr"
cmp "$TEST_DIR/qr" "$TEST_DIR/expected-qr"
[ "$(find /etc/wireguard/clients/phone-a.conf -perm 0600)" = /etc/wireguard/clients/phone-a.conf ] || fail 'profile permissions'
vpn list > "$TEST_DIR/list"
grep -q phone-a "$TEST_DIR/list" || fail list
vpn status > "$TEST_DIR/output"
expect_fail vpn add phone-a
expect_fail vpn add ../escape
expect_fail vpn export ../escape
expect_fail vpn add invalid invalid
echo 'PASS: real key generation, unique names/IPs, both modes, export, QR and permissions'
uci set network.manual=wireguard_wg0
uci add_list network.manual.allowed_ips=10.7.0.4/32
uci add_list network.manual.allowed_ips=10.7.0.5/32
uci commit network
vpn add manual-next > "$TEST_DIR/output"
grep -q '^Address = 10.7.0.6/32$' /etc/wireguard/clients/manual-next.conf || fail 'manual peer allocation'
echo 'PASS: address allocation includes all manually configured peer addresses'
uci export network > "$TEST_DIR/network-before"
touch "$TEST_DIR/fail-up"
expect_fail vpn add rollback-test
uci export network > "$TEST_DIR/network-after"
cmp "$TEST_DIR/network-before" "$TEST_DIR/network-after"
[ ! -f /etc/wireguard/clients/rollback-test.conf ] || fail 'failed add left profile'
rm "$TEST_DIR/fail-up"
vpn endpoint new.example.com > "$TEST_DIR/output"
[ "$(uci get vpn.server.endpoint)" = new.example.com ] || fail 'endpoint config'
for file in /etc/wireguard/clients/*.conf; do
    grep -q '^Endpoint = new.example.com:51820$' "$file" || fail 'endpoint profile'
done
echo 'PASS: failed add rolls back and endpoint updates saved profiles'
vpn remove phone-a > "$TEST_DIR/output"
[ ! -f /etc/wireguard/clients/phone-a.conf ] || fail removal
[ -f /etc/wireguard/clients/phone_a.conf ] || fail 'removed wrong client'
expect_fail vpn remove phone-a
uci set network.pending=interface
expect_fail vpn add pending-test
uci revert network
echo 'PASS: revocation, similar-name isolation, and pending-change protection'

# Make the default configuration match the v1.0 schema (without touching keys).
for option in cidr name pool_start pool_end lan_zone wan_zone; do
    uci -q delete "vpn.server.$option" || true
done
uci -q delete firewall.wg_vpn_forward || true
uci commit vpn
uci commit firewall
legacy_key=$(uci get network.wg0.private_key | sha256sum)
cp /etc/wireguard/clients/phone_a.conf "$TEST_DIR/legacy-profile"
vpn network show default > "$TEST_DIR/output"
grep -q '10.7.0.0/24' "$TEST_DIR/output" || fail 'legacy subnet'
vpn export phone_a > "$TEST_DIR/output"
cmp "$TEST_DIR/output" "$TEST_DIR/legacy-profile"
echo 'PASS: v1.0 configuration and saved profiles work without migration'

vpn network add work --cidr 10.20.0.0/24 --pool 10.20.0.50-10.20.0.52 --dry-run > "$TEST_DIR/output"
if uci -q get vpn.net_work >/dev/null; then fail 'named dry run wrote config'; fi
vpn network add work --cidr 10.20.0.0/24 --pool 10.20.0.50-10.20.0.52 > "$TEST_DIR/output"
work_if=$(uci get vpn.net_work.interface)
work_key=$(uci get "network.$work_if.private_key" | sha256sum)
[ "$work_key" != "$legacy_key" ] || fail 'networks share server keys'
[ "$(uci get vpn.net_work.port)" = 51821 ] || fail 'automatic port'
[ "$(uci get vpn.net_work.endpoint)" = new.example.com ] || fail 'endpoint inheritance'
[ "$(uci get network.wg0.private_key | sha256sum)" = "$legacy_key" ] || fail 'legacy key changed'
cmp /etc/wireguard/clients/phone_a.conf "$TEST_DIR/legacy-profile"
vpn add phone_a full --network work > "$TEST_DIR/output"
grep -q '^Address = 10.20.0.50/32$' /etc/wireguard/clients/work/phone_a.conf || fail 'custom pool start'
grep -q '^DNS = 10.20.0.1$' /etc/wireguard/clients/work/phone_a.conf || fail 'custom DNS'
vpn add camera --ip 10.20.0.52 --network work > "$TEST_DIR/output"
vpn add next -n work > "$TEST_DIR/output"
grep -q '^Address = 10.20.0.51/32$' /etc/wireguard/clients/work/next.conf || fail 'fixed IP reservation'
expect_fail vpn add exhausted --network work
expect_fail vpn add duplicate --network work --ip 10.20.0.52
expect_fail vpn add outside --network work --ip 10.20.0.53
expect_fail vpn add router --network work --ip 10.20.0.1
vpn export phone_a --network work > "$TEST_DIR/output"
cmp "$TEST_DIR/output" /etc/wireguard/clients/work/phone_a.conf
vpn show phone_a --network work > "$TEST_DIR/qr"
qrencode -t ANSIUTF8 < /etc/wireguard/clients/work/phone_a.conf > "$TEST_DIR/expected-qr"
cmp "$TEST_DIR/qr" "$TEST_DIR/expected-qr"
vpn list --network work > "$TEST_DIR/output"
grep -q camera "$TEST_DIR/output" || fail 'named client list'
vpn status --network work > "$TEST_DIR/output"
grep -q "$work_if" "$TEST_DIR/output" || fail 'named runtime interface'
vpn status > "$TEST_DIR/output"
grep -q wg0 "$TEST_DIR/output" || fail 'default interface was stopped'
echo 'PASS: independent network, keys, ports, pool limits, fixed IPs, QR and selectors'

vpn network add lab --cidr 10.30.0.0/23 --pool 10.30.0.255-10.30.1.2 > "$TEST_DIR/output"
vpn add first --network lab > "$TEST_DIR/output"
vpn add second --network lab > "$TEST_DIR/output"
grep -q '^Address = 10.30.0.255/32$' /etc/wireguard/clients/lab/first.conf || fail '/23 first address'
grep -q '^Address = 10.30.1.0/32$' /etc/wireguard/clients/lab/second.conf || fail 'cross-octet allocation'
grep -q '^AllowedIPs = 10.30.0.0/23, 192.168.1.0/24$' /etc/wireguard/clients/lab/first.conf || fail 'CIDR route'
vpn network add tiny --cidr 10.40.0.4/30 > "$TEST_DIR/output"
vpn add only --network tiny > "$TEST_DIR/output"
grep -q '^Address = 10.40.0.6/32$' /etc/wireguard/clients/tiny/only.conf || fail '/30 client address'
grep -q '^DNS = 10.40.0.5$' /etc/wireguard/clients/tiny/only.conf || fail '/30 gateway'
expect_fail vpn add no-space --network tiny
expect_fail vpn network add overlap --cidr 10.20.0.0/23 --dry-run
expect_fail vpn network add lan-overlap --cidr 192.168.1.128/25 --dry-run
expect_fail vpn network add public --cidr 8.8.8.0/24 --dry-run
expect_fail vpn network add too-wide --cidr 10.0.0.0/7 --dry-run
expect_fail vpn network add too-small --cidr 10.80.0.0/31 --dry-run
expect_fail vpn network add bad-pool --cidr 10.80.0.0/24 --pool 10.80.0.1-10.80.0.20 --dry-run
expect_fail vpn network add bad-pool --cidr 10.80.0.0/24 --pool 10.80.0.20-10.80.1.20 --dry-run
expect_fail vpn network add bad-pool --cidr 10.80.0.0/24 --pool 10.80.0.30-10.80.0.20 --dry-run
expect_fail vpn network add port-conflict --cidr 10.80.0.0/24 --port 51821 --dry-run
expect_fail vpn network add work --cidr 10.80.0.0/24 --dry-run
uci set network.wan.ipaddr=10.90.0.3
uci set network.wan.netmask=255.255.0.0
uci commit network
expect_fail vpn network add wan-overlap --cidr 10.90.1.0/24 --dry-run
echo 'PASS: arbitrary CIDRs, cross-octet pools, exhaustion, subnet/port conflicts and netmask checks'

vpn endpoint work.example.com --network work > "$TEST_DIR/output"
grep -q '^Endpoint = work.example.com:51821$' /etc/wireguard/clients/work/phone_a.conf || fail 'selected endpoint update'
cmp /etc/wireguard/clients/phone_a.conf "$TEST_DIR/legacy-profile"
expect_fail vpn network remove work
expect_fail vpn network remove default
touch "$TEST_DIR/fail-up"
expect_fail vpn network add failed-net --cidr 10.100.0.0/24
rm "$TEST_DIR/fail-up"
if uci -q get vpn.net_failed_hnet >/dev/null; then fail 'failed network left config'; fi
vpn status > "$TEST_DIR/output"
grep -q wg0 "$TEST_DIR/output" || fail 'failed creation stopped default network'
vpn remove camera --network work > "$TEST_DIR/output"
vpn remove next --network work > "$TEST_DIR/output"
vpn remove phone_a --network work > "$TEST_DIR/output"
vpn network remove work > "$TEST_DIR/output"
if uci -q get "network.$work_if" >/dev/null; then fail 'network interface not removed'; fi
if uci -q get firewall.wg_vpn_input_n_work >/dev/null; then fail 'network firewall not removed'; fi
vpn network list > "$TEST_DIR/output"
grep -q default "$TEST_DIR/output" || fail 'default absent from network list'
grep -q lab "$TEST_DIR/output" || fail 'lab absent from network list'
vpn export phone_a > "$TEST_DIR/output"
cmp "$TEST_DIR/output" "$TEST_DIR/legacy-profile"
echo 'PASS: scoped endpoint updates, network rollback/removal and unchanged legacy keys/profiles'
echo 'All integration checks passed. No real kernel tunnel or external traffic was tested.'
