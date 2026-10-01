#!/bin/bash

set -e

# ─── Color & Style Codes ───
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
CYAN="\e[36m"
WHITE="\e[97m"
DIM="\e[2m"
BOLD="\e[1m"
RESET="\e[0m"
BG_GREEN="\e[42m"
BG_CYAN="\e[46m"
BG_RED="\e[41m"

CHECKMARK="${GREEN}✔${RESET}"
ARROW="${CYAN}▶${RESET}"
ROCKET="${YELLOW}🚀${RESET}"
GEAR="${CYAN}⚙${RESET}"
SHIELD="${GREEN}🛡${RESET}"
LOCK="${YELLOW}🔒${RESET}"
PACKAGE="${CYAN}📦${RESET}"

TOTAL_STEPS=11
START_TIME=$(date +%s)

# ─── Versions ───
NODE_VERSION="v24.21.0"
NODE_DISTRO="linux-x64"

# ─── Helper Functions ───
line() {
    echo -e "${DIM}${CYAN}──────────────────────────────────────────────────${RESET}"
}

section() {
    local step=$1
    local title=$2
    local icon=$3

    echo ""
    line
    echo -e "  ${icon}  ${BOLD}${WHITE}[${step}/${TOTAL_STEPS}]${RESET}  ${BOLD}${CYAN}${title}${RESET}"
    line
}

success() {
    echo -e "  ${CHECKMARK}  ${GREEN}$1${RESET}"
}

info() {
    echo -e "  ${DIM}${WHITE}$1${RESET}"
}

elapsed() {
    local now=$(date +%s)
    local diff=$((now - START_TIME))
    local min=$((diff / 60))
    local sec=$((diff % 60))

    echo -e "  ${DIM}⏱  Elapsed: ${min}m ${sec}s${RESET}"
}

# ─── Banner ───
clear

echo ""
echo -e "${BOLD}${CYAN}"
echo "  ┌──────────────────────────────────────────────┐"
echo "  │                                              │"
echo -e "  │   ${WHITE} SERVER SETUP (V3.0.0) ${CYAN}                    │"
echo "  │    Server Configuration Script               │"
echo "  │                                              │"
echo -e "  │   ${DIM}Date : $(date '+%B %d, %Y  %H:%M %Z')${CYAN}        │"
echo -e "  │   ${DIM}Host : $(hostname)${CYAN}                           │"
echo "  │                                              │"
echo "  └──────────────────────────────────────────────┘"
echo -e "${RESET}"
echo ""

# ─── [1/11] Update & Upgrade ───
section 1 "Updating & Upgrading System" "${GEAR}"

sudo apt update -y
sudo apt upgrade -y

success "System updated and upgraded"
elapsed


# ─── [2/11] Install Utilities ───
section 2 "Installing Core Utilities" "${PACKAGE}"

sudo apt install -y \
    curl \
    wget \
    git \
    ufw \
    fail2ban \
    software-properties-common \
    btop \
    unzip \
    xz-utils \
    ca-certificates

success "Core utilities installed"
info "Installed: curl, wget, git, ufw, fail2ban, btop, unzip, xz-utils"
elapsed


# ─── [3/11] Install Node.js ───
section 3 "Installing Node.js LTS ${NODE_VERSION}" "${PACKAGE}"

cd /tmp

NODE_ARCHIVE="node-${NODE_VERSION}-${NODE_DISTRO}.tar.xz"
NODE_URL="https://nodejs.org/dist/${NODE_VERSION}/${NODE_ARCHIVE}"

echo -e "  ${ARROW} Downloading ${NODE_ARCHIVE}"

wget -q --show-progress "${NODE_URL}" -O "${NODE_ARCHIVE}"

echo -e "  ${ARROW} Installing Node.js to /usr/local"

sudo tar -xJf "${NODE_ARCHIVE}" \
    -C /usr/local \
    --strip-components=1

rm -f "${NODE_ARCHIVE}"

success "Node.js installed  →  $(node -v)"
info "NPM version        →  $(npm -v)"
info "Node path          →  $(which node)"
info "NPM path           →  $(which npm)"
elapsed


# ─── [4/11] Install Bun ───
section 4 "Installing Bun JavaScript Runtime" "${PACKAGE}"

echo -e "  ${ARROW} Installing latest stable Bun"

# Bun official installer
curl -fsSL https://bun.com/install | bash

# Make Bun available for the current script/session
export BUN_INSTALL="${BUN_INSTALL:-$HOME/.bun}"
export PATH="$BUN_INSTALL/bin:$PATH"

# Ensure Bun is available for future bash sessions
if [ -f "$HOME/.bashrc" ]; then
    grep -qxF 'export BUN_INSTALL="$HOME/.bun"' "$HOME/.bashrc" || \
        echo 'export BUN_INSTALL="$HOME/.bun"' >> "$HOME/.bashrc"

    grep -qxF 'export PATH="$BUN_INSTALL/bin:$PATH"' "$HOME/.bashrc" || \
        echo 'export PATH="$BUN_INSTALL/bin:$PATH"' >> "$HOME/.bashrc"
fi

if command -v bun >/dev/null 2>&1; then
    success "Bun installed  →  $(bun --version)"
    info "Bun path          →  $(which bun)"
else
    echo -e "  ${RED}✖ Bun installation failed${RESET}"
    exit 1
fi

elapsed


# ─── [5/11] Install PM2 ───
section 5 "Installing PM2 Process Manager" "${GEAR}"

sudo npm install -g pm2

sudo pm2 startup systemd --silent

success "PM2 installed and startup configured"
info "PM2 version       →  $(pm2 -v)"
elapsed


# ─── [6/11] Install NGINX ───
section 6 "Installing NGINX Web Server" "${PACKAGE}"

sudo apt install -y nginx

sudo systemctl enable nginx
sudo systemctl start nginx

success "NGINX installed and enabled"
info "$(nginx -v 2>&1)"
elapsed


# ─── [7/11] Firewall Configuration ───
section 7 "Configuring UFW Firewall" "${SHIELD}"

sudo ufw allow OpenSSH
sudo ufw allow 'Nginx Full'

sudo ufw --force enable

success "Firewall active — OpenSSH & Nginx Full allowed"
elapsed


# ─── [8/11] Fail2ban ───
section 8 "Configuring Fail2ban" "${SHIELD}"

sudo systemctl enable fail2ban
sudo systemctl start fail2ban

success "Fail2ban enabled and running"
elapsed


# ─── [9/11] Unattended Upgrades ───
section 9 "Enabling Unattended Upgrades" "${GEAR}"

sudo apt install -y unattended-upgrades

echo 'unattended-upgrades unattended-upgrades/enable_auto_updates boolean true' \
    | sudo debconf-set-selections

sudo DEBIAN_FRONTEND=noninteractive \
    dpkg-reconfigure -plow unattended-upgrades

success "Unattended upgrades configured"
elapsed


# ─── [10/11] Certbot ───
section 10 "Installing Certbot for SSL" "${LOCK}"

sudo apt install -y \
    certbot \
    python3-certbot-nginx

success "Certbot installed — ready for SSL certificates"
info "$(certbot --version 2>&1)"
elapsed


# ─── [11/11] Install Croc ───
section 11 "Installing Croc (File Transfer)" "${PACKAGE}"

curl https://getcroc.schollz.com | bash

success "Croc installed"
info "$(croc --version 2>&1)"
elapsed


# ─── Final Summary ───
END_TIME=$(date +%s)

DURATION=$((END_TIME - START_TIME))
DURATION_MIN=$((DURATION / 60))
DURATION_SEC=$((DURATION % 60))

echo ""
echo ""

echo -e "${BOLD}${GREEN}"
echo "  ┌──────────────────────────────────────────────┐"
echo "  │                                              │"
echo -e "  │   ${WHITE}✅  SERVER SETUP COMPLETE${GREEN}                  │"
echo "  │                                              │"
echo "  └──────────────────────────────────────────────┘"
echo -e "${RESET}"

echo ""
echo -e "  ${BOLD}${WHITE}Installed Components${RESET}"

line

echo -e "  ${CHECKMARK}  ${WHITE}Node.js    ${DIM}→${RESET}  $(node -v)"
echo -e "  ${CHECKMARK}  ${WHITE}NPM        ${DIM}→${RESET}  $(npm -v)"
echo -e "  ${CHECKMARK}  ${WHITE}Bun        ${DIM}→${RESET}  $(bun --version)"
echo -e "  ${CHECKMARK}  ${WHITE}PM2        ${DIM}→${RESET}  $(pm2 -v)"
echo -e "  ${CHECKMARK}  ${WHITE}NGINX      ${DIM}→${RESET}  $(nginx -v 2>&1)"
echo -e "  ${CHECKMARK}  ${WHITE}Certbot    ${DIM}→${RESET}  $(certbot --version 2>&1)"
echo -e "  ${CHECKMARK}  ${WHITE}Croc       ${DIM}→${RESET}  $(croc --version 2>&1)"
echo -e "  ${CHECKMARK}  ${WHITE}Firewall   ${DIM}→${RESET}  UFW Active"
echo -e "  ${CHECKMARK}  ${WHITE}Fail2ban   ${DIM}→${RESET}  Running"

line

echo ""
echo -e "  ${DIM}⏱  Total time: ${DURATION_MIN}m ${DURATION_SEC}s${RESET}"
echo -e "  ${DIM}📅  Completed: $(date '+%B %d, %Y at %H:%M %Z')${RESET}"
echo ""