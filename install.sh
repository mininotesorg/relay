#!/usr/bin/env bash
# Your own relay for Mininotes: installs, updates or removes a Maxima relay on this Linux server.
#
#   curl -fsSL https://raw.githubusercontent.com/mininotesorg/relay/main/install.sh | sudo bash
#   sudo bash install.sh [--port 9501] [--files 512] [--uninstall]
#
# The relay is eurobuddha's maxima-server (MIT, https://github.com/eurobuddha/maxima), downloaded from that repository at a
# fixed commit and refused unless its SHA-256 matches. It runs as its own unprivileged user, in a locked-down service, on one
# port. It touches nothing else on the server. Running this again updates it; --uninstall removes it.
set -euo pipefail

VERSION=0.4.36
COMMIT=76693eac3c94f5829373cd59125d941271a0a9b3
SHA256=f385c6d2120daf8b5e77f62c689684b35e994e649a97344fd71c03463f5a14fc
URL="https://raw.githubusercontent.com/eurobuddha/maxima/$COMMIT/dist/maxima-server-$VERSION.jar"
PORT=9501
FILES=256        # MB kept for files waiting for a device that is away
UNINSTALL=no

while [ $# -gt 0 ]; do
    case "$1" in
        --port) PORT="$2"; shift 2 ;;
        --files) FILES="$2"; shift 2 ;;
        --uninstall) UNINSTALL=yes; shift ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

[ "$(id -u)" -eq 0 ] || { echo "Run it as root: sudo bash install.sh" >&2; exit 1; }

if [ "$UNINSTALL" = yes ]; then
    systemctl disable --now maxima-relay 2>/dev/null || true
    rm -f /etc/systemd/system/maxima-relay.service
    systemctl daemon-reload
    if command -v ufw >/dev/null 2>&1; then ufw delete allow "$PORT/tcp" >/dev/null 2>&1 || true; fi
    rm -rf /opt/maxima
    echo "Removed. The relay's identity is kept in /var/lib/maxima; delete that folder too to forget it."
    exit 0
fi

echo "1/5  Java"
if ! command -v java >/dev/null 2>&1; then
    if command -v apt-get >/dev/null 2>&1; then
        DEBIAN_FRONTEND=noninteractive apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq default-jre-headless >/dev/null
    elif command -v dnf >/dev/null 2>&1; then dnf install -y -q java-21-openjdk-headless
    else echo "Install Java 11 or newer, then run this again." >&2; exit 1; fi
fi
echo "     $(java -version 2>&1 | head -1)"

echo "2/5  The relay program"
id maxima >/dev/null 2>&1 || useradd --system --home /var/lib/maxima --shell /usr/sbin/nologin maxima
mkdir -p /opt/maxima /var/lib/maxima
chown -R maxima:maxima /var/lib/maxima && chmod 700 /var/lib/maxima
curl -fsSL "$URL" -o "/opt/maxima/maxima-server-$VERSION.jar.part"
GOT=$(sha256sum "/opt/maxima/maxima-server-$VERSION.jar.part" | cut -d' ' -f1)
if [ "$GOT" != "$SHA256" ]; then
    rm -f "/opt/maxima/maxima-server-$VERSION.jar.part"
    echo "The download does not match its SHA-256. Nothing was changed." >&2; exit 1
fi
mv "/opt/maxima/maxima-server-$VERSION.jar.part" "/opt/maxima/maxima-server-$VERSION.jar"
ln -sf "maxima-server-$VERSION.jar" /opt/maxima/maxima-server.jar
chmod 644 "/opt/maxima/maxima-server-$VERSION.jar"
echo "     maxima-server $VERSION, SHA-256 checked"

echo "3/5  The service"
cat > /etc/systemd/system/maxima-relay.service <<UNIT
[Unit]
Description=Maxima relay for Mininotes (maxima-server $VERSION)
Documentation=https://github.com/mininotesorg/relay
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=300
StartLimitBurst=5

[Service]
Type=simple
User=maxima
Group=maxima
ExecStart=/usr/bin/env java -Xmx128m -jar /opt/maxima/maxima-server.jar --port $PORT --data /var/lib/maxima --blobstore $FILES
Restart=on-failure
RestartSec=10
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/maxima
UMask=0077
PrivateDevices=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
CapabilityBoundingSet=
RestrictSUIDSGID=true
RestrictNamespaces=true
LockPersonality=true
SystemCallArchitectures=native
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
MemoryMax=384M
OOMScoreAdjust=500
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
UNIT

echo "4/5  The firewall"
if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | head -1 | grep -qw active; then
    ufw allow "$PORT/tcp" comment 'Maxima relay' >/dev/null; echo "     ufw: port $PORT open"
elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    firewall-cmd --permanent --add-port="$PORT/tcp" >/dev/null && firewall-cmd --reload >/dev/null; echo "     firewalld: port $PORT open"
else
    echo "     No firewall on this server to open."
fi

echo "5/5  Starting"
systemctl daemon-reload
systemctl enable maxima-relay >/dev/null 2>&1
systemctl restart maxima-relay
sleep 6
if ! ss -ltn | grep -q ":$PORT "; then
    echo "The relay did not start. Its last lines:" >&2; journalctl -u maxima-relay -n 20 --no-pager >&2; exit 1
fi

IP=$(curl -fsS --max-time 10 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')
echo
echo "Your relay is running. In Mininotes: Settings, Relays, Add a relay:"
echo
echo "    $IP:$PORT"
echo
echo "If your provider has a firewall of its own (Vultr, Hetzner, AWS...), open TCP $PORT there too."
