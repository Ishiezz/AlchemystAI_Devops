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

echo "=== Inference worker initialization (III_URL=$${III_URL}) ===" >&2

apt-get update
apt-get install -y curl git ca-certificates python3 python3-pip python3-venv build-essential

wait_for_tcp "$${III_ENGINE_HOST}" "$${III_ENGINE_PORT}"

clone_repo
WORKER_DIR="/opt/alchemyst/AlchemystAI_Devops/quickstart/workers/inference-worker"
cd "$${WORKER_DIR}"

python3 -m venv /opt/alchemyst/venv
/opt/alchemyst/venv/bin/pip install --upgrade pip
/opt/alchemyst/venv/bin/pip install torch --index-url https://download.pytorch.org/whl/cpu
/opt/alchemyst/venv/bin/pip install "iii-sdk==0.12.0" "transformers>=5.0,<6" "gguf==0.14.0" accelerate

cat > /etc/systemd/system/inference-worker.service <<EOF
[Unit]
Description=Alchemyst Inference Worker (Python)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=$${WORKER_DIR}
Environment=III_URL=$${III_URL}
Environment=PYTHONUNBUFFERED=1
Environment=PATH=/opt/alchemyst/venv/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=/opt/alchemyst/venv/bin/python inference_worker.py
Restart=on-failure
RestartSec=15
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable inference-worker
systemctl start inference-worker

echo "=== Inference worker initialization complete ===" >&2
