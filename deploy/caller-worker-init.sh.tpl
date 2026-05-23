#!/bin/bash
set -euo pipefail

export HOME=/root
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export DEBIAN_FRONTEND=noninteractive

cat > /tmp/alchemyst-common.sh <<'COMMONSCRIPT'
${common_sh}
COMMONSCRIPT
source /tmp/alchemyst-common.sh

III_ENGINE_HOST="${iii_engine_host}"
III_ENGINE_PORT="${iii_engine_port}"
III_URL="ws://$${III_ENGINE_HOST}:$${III_ENGINE_PORT}"

echo "=== Caller worker initialization (III_URL=$${III_URL}) ===" >&2

apt-get update
apt-get install -y curl git ca-certificates unzip

wait_for_tcp "$${III_ENGINE_HOST}" "$${III_ENGINE_PORT}"

curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs
curl -fsSL https://bun.sh/install | bash
export PATH="/root/.bun/bin:/usr/local/bin:$${PATH}"

clone_repo
WORKER_DIR="/opt/alchemyst/AlchemystAI_Devops/quickstart/workers/caller-worker"
cd "$${WORKER_DIR}"
npm install iii-sdk@0.12.0
npm install

cat > /etc/systemd/system/caller-worker.service <<EOF
[Unit]
Description=Alchemyst Caller Worker (TypeScript)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=$${WORKER_DIR}
Environment=III_URL=$${III_URL}
Environment=NODE_ENV=production
Environment=PATH=/root/.bun/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=/root/.bun/bin/bun src/worker.ts
Restart=on-failure
RestartSec=15
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable caller-worker
systemctl start caller-worker

echo "=== Caller worker initialization complete ===" >&2
