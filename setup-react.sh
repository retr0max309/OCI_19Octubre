#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

sudo apt-get update
sudo apt-get install -y ca-certificates curl nginx rsync

if ! command -v node >/dev/null 2>&1 || ! node -e 'process.exit(Number(process.versions.node.split(".")[0]) >= 22 ? 0 : 1)'; then
  curl -fsSL https://deb.nodesource.com/setup_24.x -o /tmp/nodesource_setup.sh
  sudo -E bash /tmp/nodesource_setup.sh
  sudo apt-get install -y nodejs
fi

cd /home/ubuntu/react-app
npm ci
npm run build

sudo mkdir -p /var/www/html
sudo rsync -a --delete dist/ /var/www/html/
sudo chown -R www-data:www-data /var/www/html
if command -v ufw >/dev/null 2>&1; then
  sudo ufw allow 80/tcp
fi
sudo iptables -C INPUT -p tcp --dport 80 -j ACCEPT || sudo iptables -I INPUT -p tcp --dport 80 -j ACCEPT
sudo systemctl enable --now nginx
sudo systemctl reload nginx
