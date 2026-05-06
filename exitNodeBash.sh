#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------------
#  CONFIGURATION – tweak only if you move the VPS or want a new IP
# -------------------------------------------------------------
IP="82.115.19.57"                         # <-- your public IP
WORKDIR="/opt/exit-node"                  # where we keep all files
EXIT_NODE_URL="https://raw.githubusercontent.com/therealaleph/MasterHttpRelayVPN-RUST/main/src/exit_node.ts"

# -------------------------------------------------------------
#  1️⃣  Ask for a PSK or generate one automatically
# -------------------------------------------------------------
PSK=${1:-}
if [[ -z "$PSK" ]]; then
    read -rp "Enter your pre‑shared key (leave blank → random): " PSK
fi

if [[ -z "$PSK" ]]; then
    echo "🔑 Generating 32‑byte secret …"
    PSK=$(openssl rand -hex 32)
else
    # keep exactly what the user typed
    PSK="$PSK"
fi
export PSK   # make it visible to systemd later

# -------------------------------------------------------------
#  2️⃣  Install Deno if not already present
# -------------------------------------------------------------
if ! command -v deno >/dev/null 2>&1; then
    echo "🛠️ Installing Deno ..."
    curl -fsSL https://deno.land/x/install/install.sh | sh
    export PATH="$HOME/.deno/bin:$PATH"
fi

# -------------------------------------------------------------
#  3️⃣  Prepare the working directory & pull the handler file
# -------------------------------------------------------------
mkdir -p "$WORKDIR" && cd "$WORKDIR"

echo "📥 Downloading exit_node.ts ..."
curl -fsSL "$EXIT_NODE_URL" > exit_node.ts.tmp

echo "🔧 Replacing the PSK placeholder …"
sed "s|const PSK = \"CHANGE_ME_TO_A_STRONG_SECRET\";|const PSK = \"$PSK\";|" \
    exit_node.ts.tmp > exit_node.ts
rm -f exit_node.ts.tmp

# -------------------------------------------------------------
#  4️⃣  Install nginx (if not already there)
# -------------------------------------------------------------
if ! command -v nginx >/dev/null 2>&1; then
    echo "🛠️ Installing nginx ..."
    sudo apt-get update && sudo apt-get install -y nginx
fi

# -------------------------------------------------------------
#  5️⃣  Generate a self‑signed cert for the raw IP (no domain needed)
# -------------------------------------------------------------
CERT_DIR="/etc/nginx/ssl"
sudo mkdir -p "$CERT_DIR"

if [[ ! -f "$CERT_DIR/server.crt" || ! -f "$CERT_DIR/server.key" ]]; then
    echo "🔒 Creating temporary TLS certificate for $IP ..."
    sudo openssl req -x509 -nodes -days 365 \
        -subj "/CN=$IP" \
        -newkey rsa:2048 \
        -keyout "$CERT_DIR/server.key" \
        -out "$CERT_DIR/server.crt"
fi

# -------------------------------------------------------------
#  6️⃣  nginx reverse‑proxy to Deno on port 8443
# -------------------------------------------------------------
NGINX_CONF="/etc/nginx/sites-available/exit-node"

sudo tee "$NGINX_CONF" > /dev/null <<EOF
server {
    listen 443 ssl;
    server_name $IP;

    ssl_certificate     $CERT_DIR/server.crt;
    ssl_certificate_key $CERT_DIR/server.key;

    location / {
        proxy_pass http://127.0.0.1:8443;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF

sudo ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/exit-node
sudo nginx -t && sudo systemctl reload nginx

# -------------------------------------------------------------
#  7️⃣  Create a systemd unit that runs Deno with the handler
# -------------------------------------------------------------
SERVICE="/etc/systemd/system/exit-node.service"

sudo tee "$SERVICE" > /dev/null <<EOF
[Unit]
Description=MasterHttpRelay exit node (Cloudflare‑bypass)
After=network.target

[Service]
User=$USER
WorkingDirectory=$WORKDIR
Environment="PSK=\$PSK"
ExecStart=/usr/bin/env deno run --allow-net --unstable exit_node.ts
Restart=always
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=exit-node

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now exit-node.service

# -------------------------------------------------------------
#  8️⃣  Final report
# -------------------------------------------------------------
echo "✅ Exit node is ready and running."
echo ""
echo "• HTTPS URL: https://$IP/"
echo "• PSK (copy it to your mhrv‑rs config): $PSK"
echo ""
echo "If you ever need to change the PSK, edit /opt/exit-node/exit_node.ts"
echo "then run: sudo systemctl restart exit-node.service"
