#!/bin/bash
# Tier 2 (app) VM startup script
[ -f /var/lib/sf-done ] && exit 0
md() { curl -s -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/$1"; }
apt-get update -y && apt-get install -y python3-flask python3-psycopg2
mkdir -p /opt/streamflix
md app-py > /opt/streamflix/app.py
cat > /etc/systemd/system/streamflix.service <<UNIT
[Unit]
Description=StreamFlix API
After=network.target
[Service]
Environment=DB_HOST=10.10.3.10 DB_NAME=streamflix DB_USER=streamflix DB_PASSWORD=streamflix123
ExecStart=/usr/bin/python3 /opt/streamflix/app.py
Restart=always
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now streamflix
touch /var/lib/sf-done
