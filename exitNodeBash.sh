#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------------
#  CONFIGURATION (you can tweak these if you wish)
# ------------------------------------------------------------------
IP="82.115.19.57"                     # your VPS IP – change only if you move hosts
WORKDIR="/opt/exit-node"              # where the script will store files
EXIT_NODE_URL=(
    "https://raw.githubusercontent.com/"
    "therealaleph/MasterHttpRelayVPN-RUST/main/src/exit_node.ts"
)                                     # URL to the raw source file

# ------------------------------------------------------------------
#  1️⃣  Ask for or generate a PSK (pre‑shared key)
# ------------------------------------------------------------------
PSK_INPUT=${1:-}
if [[ -z "$PSK_INPUT" ]]; then
  read -rp "Enter your PSK (leave blank → random hex): " PSK_INPUT
fi

if [[ -z "$PSK_INPUT" ]]; then
    echo "🔑 Generating a random 32‑byte secret for you..."
    PSK=$(openssl rand -hex 32)
else
    PSK="$PSK_INPUT"
fi
export PSK   # make it available to the service later

# ------------------------------------------------------------------
#  2️⃣  Install Deno if missing
# ------------------------------------------------------------------
if ! command -v deno >/dev/null 2>&1; then
  echo "🛠️ Installing Deno ..."
  curl -fsSL https://deno.land/x/install/install.sh | sh
  export PATH="$HOME/.deno/bin:$PATH"
fi

# ------------------------------------------------------------------
#  3️⃣  Prepare working directory & download the handler
# ------------------------------------------------------------------
mkdir -p "$WORKDIR"
cd "$WORKDIR"

echo "📥 Downloading exit_node.ts ..."
curl -fsSL "${EXIT_NODE_URL[*]}" > exit_node.ts.tmp

echo "🔧 Replacing PSK placeholder ..."
sed "s|const PSK = \"CHANGE_ME_TO_A_STRONG_SECRET\";|const PSK = \"$PSK\";|" \
    exit_node.ts.tmp > exit_node.ts
rm -f exit_node.ts.tmp

# ------------------------------------------------------------------
#  4️⃣  Install nginx (if not already present)
# ------------------------------------------------------------------
if ! command -v nginx >/dev/null 2>&1; then
  echo "🛠️ Installing nginx ..."
  sudo apt-get update && sudo apt-get install -y nginx
fi

# ------------------------------------------------------------------
#  5️⃣  Generate a self‑signed cert for the IP (no domain needed)
# ------------------------------------------------------------------
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

# ------------------------------------------------------------------
#  6️⃣  Configure nginx as a reverse proxy to Deno
# ------------------------------------------------------------------
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

# ------------------------------------------------------------------
#  7️⃣  Create a systemd unit to run Deno
# ------------------------------------------------------------------
SERVICE="/etc/systemd/system/exit-node.service"

sudo tee "$SERVICE" > /dev/null <<EOF
[Unit]
Description=Exit node for mhrv-rs
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

# ------------------------------------------------------------------
#  8️⃣  Final report
# ------------------------------------------------------------------
echo "✅ Done! The exit node is up."
echo "• HTTPS endpoint: https://$IP/"
echo "• PSK (copy this – you’ll need it in mhrv‑rs config): $PSK"
echo ""
echo "If you want to change the PSK later, edit exit_node.ts and restart:"
echo "  sudo systemctl restart exit-node.service"
