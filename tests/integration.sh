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
    show) [ -f "$TEST_DIR/up" ] && echo 'interface: wg0';;
    *) exec "$REAL_WG" "$@";;
esac
EOF
cat > "$TEST_DIR/bin/ifdown" <<'EOF'
#!/bin/sh
rm -f "$TEST_DIR/up"
EOF
cat > "$TEST_DIR/bin/ifup" <<'EOF'
#!/bin/sh
[ ! -f "$TEST_DIR/fail-up" ] || exit 1
touch "$TEST_DIR/up"
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
    rm -f /etc/config/vpn "$TEST_DIR/up" "$TEST_DIR/fail-up"
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
[ "$(vpn version)" = 1.0.0 ] || fail version
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
echo 'All integration checks passed. No real kernel tunnel or external traffic was tested.'
