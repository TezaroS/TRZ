#!/usr/bin/env bash
# ------------------------------------------------------------------
# GooseRelayVPN – Server auto‑installer
#   Target VPS: 82.115.19.57
#
# Author:   chatGPT (for educational purposes)
# License:  MIT (copy of the original repo licence is used)
# ------------------------------------------------------------------

set -euo pipefail

# ---------- Helper Functions --------------------------------------
die() { echo "ERROR: $*" >&2; exit 1; }

require_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        die "This script must be run as root (or via sudo)."
    fi
}

apt_install() {
    local packages=("$@")
    echo "Installing required packages: ${packages[*]}"
    apt-get update -y >/dev/null
    DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}" > /dev/null
}

yum_install() {
    local packages=("$@")
    echo "Installing required packages: ${packages[*]}"
    yum makecache fast -q
    yum install -y "${packages[@]}" >/dev/null
}

install_ufw() {
    if ! command -v ufw &>/dev/null; then
        echo "Installing ufw..."
        if command -v apt-get &>/dev/null; then
            apt_install ufw
        elif command -v yum &>/dev/null; then
            yum_install ufw
        else
            die "Neither apt nor yum found – cannot install ufw."
        fi
    fi
}

open_port() {
    local port=${1}
    echo "Opening TCP $port in the firewall..."
    if ! ufw status | grep -q "$port"; then
        ufw allow "${port}/tcp" >/dev/null
    else
        echo "Port $port already open."
    fi
}

# ---------- Main Script --------------------------------------------
require_root

echo "=== GooseRelayVPN Server Auto‑Installer ==="
echo "Target IP: 82.115.19.57"
echo ""

# 1️⃣  Install dependencies
install_ufw

# 2️⃣  Grab the latest release tag from GitHub
echo "Fetching latest GooseRelayVPN release information..."
release_tag=$(curl -s https://api.github.com/repos/kianmhz/GooseRelayVPN/releases/latest \
    | grep -oP '"tag_name":\s*"\K[^"]+')
[ -n "$release_tag" ] || die "Could not fetch the latest tag from GitHub."

echo "Latest release: $release_tag"

# 3️⃣  Download / extract
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

download_url="https://github.com/kianmhz/GooseRelayVPN/releases/download/${release_tag}/GooseRelayVPN-server-${release_tag}-linux-amd64.tar.gz"

echo "Downloading server binary ($download_url)..."
wget -qO "${tmpdir}/server.tar.gz" "$download_url"

echo "Extracting..."
mkdir -p /opt/goose-relay
tar --strip-components=1 -xf "${tmpdir}/server.tar.gz" -C /opt/goose-relay

# Make the binary executable (just in case)
chmod +x /opt/goose-relay/goose-server

# 4️⃣  Create configuration directory & ask for key
config_dir="/root/goose-relay"
mkdir -p "$config_dir"

echo ""
read -rp "Enter the 64‑character hex AES‑256 tunnel key (same as on the client): " tunnel_key
[[ ${#tunnel_key} -eq 64 ]] || die "Key must be exactly 64 hex characters."

cat >"$config_dir/server_config.json" <<EOF
{
  "server_host": "0.0.0.0",
  "server_port": 8443,
  "tunnel_key": "$tunnel_key"
}
EOF

echo ""
echo "Configuration written to $config_dir/server_config.json"

# 5️⃣  Open firewall port
open_port 8443

# 6️⃣  Create systemd service (optional)
cat >/etc/systemd/system/goose-relay.service <<'EOL'
[Unit]
Description=GooseRelayVPN exit server
After=network.target

[Service]
Type=simple
WorkingDirectory=/root/goose-relay
ExecStart=/opt/goose-relay/goose-server -config /root/goose-relay/server_config.json
Restart=always
RestartSec=5
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=goose-relay

[Install]
WantedBy=multi-user.target
EOL

echo ""
systemctl daemon-reload
systemctl enable goose-relay.service >/dev/null 2>&1 || true
systemctl start goose-relay.service

# 7️⃣  Final status
echo "-------------------------------------------------"
if systemctl is-active --quiet goose-relay.service; then
    echo "✅ GooseRelayVPN server is running as a systemd service."
else
    echo "⚠️  Server did not start automatically."
    echo "Try: sudo systemctl start goose-relay.service"
fi

echo ""
echo "All done! To stop or restart the service:"
echo "   sudo systemctl stop/goose-relay.service"
echo "   sudo systemctl restart/goose-relay.service"

echo ""
echo "Check logs with: journalctl -u goose-relay.service -f"
