#!/bin/bash
# startup-script.sh — VM bootstrap for the ttw MIG (mirrors the journey's
# EC2 UserData, ported to Debian 12 + GCP). Self-configuring: everything is
# derived from the metadata server, so the instance template needs no
# per-project templating.
set -euxo pipefail
exec > /var/log/shop-boot.log 2>&1

MD="http://metadata.google.internal/computeMetadata/v1"
PROJECT=$(curl -fsS -H "Metadata-Flavor: Google" "${MD}/project/project-id")

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y python3-venv python3-pip curl

useradd -r -s /usr/sbin/nologin shop || true
mkdir -p /opt/shop/app
gcloud storage cp "gs://ttw-assets-${PROJECT}/app/app.tar.gz" /opt/shop/app.tar.gz
tar xzf /opt/shop/app.tar.gz -C /opt/shop/app

# Debian 12 is PEP 668 externally-managed — venv instead of system pip.
python3 -m venv /opt/shop/venv
/opt/shop/venv/bin/pip install --no-cache-dir -r /opt/shop/app/requirements.txt

# Cloud SQL Auth Proxy v2, pinned v2.14.2 (binary URL pattern verified
# 2026-07). Tunnels 127.0.0.1:5432 -> ttw-postgres as the instance SA.
curl -fsSL -o /usr/local/bin/cloud-sql-proxy \
  "https://storage.googleapis.com/cloud-sql-connectors/cloud-sql-proxy/v2.14.2/cloud-sql-proxy.linux.amd64"
chmod +x /usr/local/bin/cloud-sql-proxy

cat > /etc/shop.env <<ENV
DB_HOST=127.0.0.1
DB_PORT=5432
DB_NAME=online_shop
SECRET_ID_DB=ttw-db-password
SECRET_ID_LEGACY=ttw-legacy-api-key
ASSETS_BUCKET=ttw-assets-${PROJECT}
GCP_PROJECT=${PROJECT}
ENV

cat > /etc/systemd/system/cloud-sql-proxy.service <<UNIT
[Unit]
Description=Cloud SQL Auth Proxy (ttw-postgres)
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/local/bin/cloud-sql-proxy --address 127.0.0.1 --port 5432 ${PROJECT}:asia-northeast1:ttw-postgres
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

cat > /etc/systemd/system/shop.service <<'UNIT'
[Unit]
Description=Online shop web store (gunicorn)
After=cloud-sql-proxy.service network-online.target
Wants=cloud-sql-proxy.service

[Service]
User=shop
WorkingDirectory=/opt/shop/app
EnvironmentFile=/etc/shop.env
ExecStart=/opt/shop/venv/bin/gunicorn --workers 2 --bind 0.0.0.0:8000 app:app
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

chown -R shop:shop /opt/shop
systemctl daemon-reload
systemctl enable --now cloud-sql-proxy.service
systemctl enable --now shop.service
