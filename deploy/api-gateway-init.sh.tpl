#!/bin/bash
set -euo pipefail

export HOME=/root
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export DEBIAN_FRONTEND=noninteractive

cat > /tmp/alchemyst-common.sh <<'COMMONSCRIPT'
${common_sh}
COMMONSCRIPT
source /tmp/alchemyst-common.sh

echo "=== API gateway (iii engine) initialization ===" >&2

apt-get update
apt-get install -y curl git ca-certificates jq

install_iii_cli
export PATH="/root/.local/bin:$${PATH}"

clone_repo

mkdir -p /opt/alchemyst/data
cp /opt/alchemyst/AlchemystAI_Devops/deploy/engine-config.yaml /opt/alchemyst/config.yaml

cat > /etc/systemd/system/iii-engine.service <<'EOF'
[Unit]
Description=iii Engine (RPC mesh + HTTP gateway)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/alchemyst
Environment=PATH=/root/.local/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=/root/.local/bin/iii --config /opt/alchemyst/config.yaml
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable iii-engine
systemctl start iii-engine

echo "=== API gateway initialization complete ===" >&2
