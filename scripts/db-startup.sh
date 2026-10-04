#!/bin/bash
# Tier 3 (data) VM startup script
[ -f /var/lib/sf-done ] && exit 0
md() { curl -s -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/$1"; }
apt-get update -y && apt-get install -y postgresql
CONF=$(ls -d /etc/postgresql/*/main)
echo "listen_addresses='*'" >> $CONF/postgresql.conf
echo "host streamflix streamflix 10.10.2.0/24 scram-sha-256" >> $CONF/pg_hba.conf   # only app-subnet
systemctl restart postgresql
sudo -u postgres psql -c "CREATE USER streamflix WITH PASSWORD 'streamflix123';"
sudo -u postgres createdb -O streamflix streamflix
md init-sql > /tmp/init.sql
PGPASSWORD=streamflix123 psql -h 127.0.0.1 -U streamflix -d streamflix -f /tmp/init.sql
touch /var/lib/sf-done
