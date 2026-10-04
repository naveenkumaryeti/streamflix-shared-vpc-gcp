#!/bin/bash
# Tier 1 (web) VM startup script
[ -f /var/lib/sf-done ] && exit 0
md() { curl -s -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/$1"; }
apt-get update -y && apt-get install -y nginx
md index-html > /var/www/html/index.html
md nginx-conf | sed -e 's#http://backend:5000#http://10.10.2.10:5000#' \
                    -e 's#/usr/share/nginx/html#/var/www/html#' > /etc/nginx/sites-available/default
systemctl restart nginx
touch /var/lib/sf-done
