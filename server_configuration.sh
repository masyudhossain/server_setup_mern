#!/bin/bash
set -e

GREEN="\e[32m"
BOLD="\e[1m"
RESET="\e[0m"

section() {
  echo -e "${GREEN}==========================================${RESET}"
  echo -e "${BOLD}${GREEN}$1${RESET}"
  echo -e "${GREEN}==========================================${RESET}"
}

section "Initial Server Setup (Next.js + Payload CMS)"

# 1. Update system
section "[1/9] Updating system..."
sudo apt update -y && sudo apt upgrade -y

# 2. Utilities
section "[2/9] Installing utilities..."
sudo apt install -y curl wget git ufw fail2ban software-properties-common

# 3. Install Node.js 20 LTS (SAFE)
section "[3/9] Installing Node.js 20 LTS..."
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs

node -v
npm -v

# 4. PM2
section "[4/9] Installing PM2..."
sudo npm install -g pm2
sudo pm2 startup systemd -u ubuntu --hp /home/ubuntu
pm2 save

# 5. Nginx
section "[5/9] Installing NGINX..."
sudo apt install -y nginx
sudo systemctl enable nginx
sudo systemctl start nginx

# 6. Firewall
section "[6/9] Configuring UFW..."
sudo ufw allow OpenSSH
sudo ufw allow 'Nginx Full'
sudo ufw --force enable

# 7. Fail2ban
section "[7/9] Enabling Fail2Ban..."
sudo systemctl enable fail2ban
sudo systemctl start fail2ban

# 8. Certbot
section "[8/9] Installing Certbot..."
sudo apt install -y certbot python3-certbot-nginx

# 9. Done
section "[9/9] Setup Complete"
echo "Node:    $(node -v)"
echo "NPM:     $(npm -v)"
echo "PM2:     $(pm2 -v)"
echo "NGINX:   $(nginx -v 2>&1)"
echo "UFW:     Enabled"
echo "Fail2Ban: Enabled"
echo -e "${GREEN}Server is ready for Next.js and Payload CMS deployment!${RESET}"