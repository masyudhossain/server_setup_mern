
#!/usr/bin/env bash
# Server Provisioning Script V4.2.0
# Target: Ubuntu 24.04 / 26.04 LTS x86_64
# Installs: Node.js 24 LTS, latest npm, Bun, PM2, NGINX,
# UFW, Fail2ban, unattended upgrades, Certbot and Croc.

set -Eeuo pipefail
umask 027

export DEBIAN_FRONTEND=noninteractive
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# -------------------- Configuration --------------------

NODE_MAJOR=24
BACKUP_DIR="/root/server-setup-backups/$(date +%Y%m%d-%H%M%S)"
TMP_DIR="$(mktemp -d)"

# -------------------- Logging --------------------------

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

die() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
    exit 1
}

section() {
    echo
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${BLUE} $*${NC}"
    echo -e "${BLUE}==================================================${NC}"
}

cleanup() {
    rm -rf -- "$TMP_DIR"
}

trap cleanup EXIT

# -------------------- Preflight ------------------------

[[ $EUID -eq 0 ]] || die "Run this script as root: sudo bash setup.sh"

[[ -r /etc/os-release ]] || die "Cannot identify the operating system."
# shellcheck disable=SC1091
source /etc/os-release

[[ "${ID:-}" == "ubuntu" ]] || die "This script supports Ubuntu only."
case "${VERSION_ID:-}" in
    24.04|26.04) ;;
    *) die "Supported Ubuntu versions: 24.04 and 26.04; detected ${VERSION_ID:-unknown}." ;;
esac

[[ "$(dpkg --print-architecture)" == "amd64" ]] ||
    die "This script currently supports amd64/x86_64 only."

command -v systemctl >/dev/null 2>&1 ||
    die "systemd is required."

if [[ -d /var/www ]]; then
    warn "/var/www exists. Existing applications will not be intentionally removed."
fi

echo
echo "This script will install or update system packages and security settings."
echo "Use it on a fresh server. Review the script before executing it."
echo
read -r -p "Type YES to continue: " CONFIRM
[[ "$CONFIRM" == "YES" ]] || die "Cancelled."

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

# -------------------- 1. System Update ------------------

section "1/11 - Updating Ubuntu"

apt-get update
apt-get upgrade -y
apt-get install -y \
    ca-certificates \
    curl \
    wget \
    gnupg \
    jq \
    git \
    unzip \
    xz-utils \
    tar \
    ufw \
    fail2ban \
    openssh-server \
    software-properties-common \
    btop \
    unattended-upgrades \
    apt-transport-https

# -------------------- 2. Node.js ------------------------

section "2/11 - Installing Node.js ${NODE_MAJOR} LTS"

# Determine the latest published Node.js 24.x release.
NODE_VERSION="$(
    curl -fsSL https://nodejs.org/dist/index.json |
    jq -er '
        [.[] | select(.version | test("^v24\\."))][0].version
    '
)"

[[ "$NODE_VERSION" =~ ^v24\.[0-9]+\.[0-9]+$ ]] ||
    die "Could not determine a valid Node.js 24 release."

NODE_ARCHIVE="node-${NODE_VERSION}-linux-x64.tar.xz"
NODE_URL="https://nodejs.org/dist/${NODE_VERSION}/${NODE_ARCHIVE}"

log "Selected Node.js ${NODE_VERSION}"

# Back up existing executables and global npm packages, if present.
for path in \
    /usr/local/bin/node \
    /usr/local/bin/npm \
    /usr/local/bin/npx \
    /usr/local/bin/corepack \
    /usr/local/lib/node_modules
do
    if [[ -e "$path" || -L "$path" ]]; then
        cp -a --parents "$path" "$BACKUP_DIR/"
    fi
done

curl -fsSL "$NODE_URL" -o "$TMP_DIR/$NODE_ARCHIVE"
curl -fsSL \
    "https://nodejs.org/dist/${NODE_VERSION}/SHASUMS256.txt" \
    -o "$TMP_DIR/SHASUMS256.txt"

(
    cd "$TMP_DIR"
    grep -F "  ${NODE_ARCHIVE}" SHASUMS256.txt |
        sha256sum --check -
) || die "Node.js checksum verification failed."

tar -xJf "$TMP_DIR/$NODE_ARCHIVE" \
    -C /usr/local \
    --strip-components=1 \
    --no-same-owner

hash -r

node --version
npm --version

# -------------------- 3. Latest npm ---------------------

section "3/11 - Installing latest stable npm"

# Node.js bundles npm, but the bundled version may not be the latest.
# Update npm separately, then verify that it works.
npm install --global npm@latest

hash -r

log "Node.js: $(node --version)"
log "npm:     $(npm --version)"

npm --version >/dev/null ||
    die "npm verification failed."


# -------------------- 4. Bun ----------------------------

section "4/11 - Installing or updating Bun"

export BUN_INSTALL="/root/.bun"
export PATH="${BUN_INSTALL}/bin:${PATH}"

# Install or update Bun using the official installer.
curl -fsSL https://bun.sh/install -o "$TMP_DIR/bun-install.sh"
bash "$TMP_DIR/bun-install.sh"

BUN_BIN="/root/.bun/bin/bun"

[[ -x "$BUN_BIN" ]] ||
    die "Bun binary was not found after installation."

# Make Bun available in future root Bash sessions.
for PROFILE_FILE in /root/.bashrc /root/.profile; do
    touch "$PROFILE_FILE"

    if ! grep -Fq '# Bun PATH configuration' "$PROFILE_FILE"; then
        cat >> "$PROFILE_FILE" <<'EOF'

# Bun PATH configuration
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
EOF
    fi
done

# Verify the binary directly, independently of shell configuration.
log "Bun: $("$BUN_BIN" --version)"


# -------------------- 5. PM2 ----------------------------

section "5/11 - Installing latest stable PM2"

npm install --global pm2@latest

command -v pm2 >/dev/null 2>&1 ||
    die "PM2 installation failed."

log "PM2: $(pm2 --version)"

# Configure PM2 to start at boot for root.
pm2 startup systemd -u root --hp /root

systemctl daemon-reload

# No application processes are started by this script.

# -------------------- 6. NGINX --------------------------

section "6/11 - Installing NGINX"

# Use Ubuntu's own repository for Ubuntu 26.04 compatibility.
# This installs the latest NGINX package available from the
# configured Ubuntu repositories, not necessarily upstream mainline.
apt-get install -y nginx

nginx -t || die "NGINX configuration test failed."

systemctl enable --now nginx

log "NGINX: $(nginx -v 2>&1)"

# -------------------- 7. Firewall -----------------------

section "7/11 - Configuring UFW"

# Keep SSH access open before enabling the firewall.
ufw allow OpenSSH
ufw allow 'Nginx Full'

ufw --force enable
ufw status verbose

# -------------------- 8. Fail2ban -----------------------

section "8/11 - Configuring Fail2ban"

apt-get install -y fail2ban python3-systemd

mkdir -p /etc/fail2ban/jail.d

# Use the systemd journal for SSH authentication logs.
cat > /etc/fail2ban/jail.d/sshd.local <<'EOF'
[sshd]
enabled = true
backend = systemd
maxretry = 3
findtime = 10m
bantime = 1d
EOF

fail2ban-client -t ||
    die "Fail2ban configuration test failed."

systemctl enable fail2ban
systemctl reset-failed fail2ban || true

# Restart Fail2ban, then wait for its client socket to become responsive.
# systemctl is-active alone is not sufficient: the daemon can be active
# briefly before fail2ban.sock is ready.
if ! systemctl restart fail2ban; then
    warn "Fail2ban failed to restart. Recent service logs:"
    journalctl -u fail2ban -n 80 --no-pager || true
    die "Fail2ban could not start. Fix the service error before continuing."
fi

FAIL2BAN_READY=false
for attempt in {1..20}; do
    if systemctl is-active --quiet fail2ban &&
       fail2ban-client ping >/dev/null 2>&1; then
        FAIL2BAN_READY=true
        break
    fi
    sleep 1
done

if [[ "$FAIL2BAN_READY" != "true" ]]; then
    warn "Fail2ban did not become responsive. Recent service logs:"
    systemctl status fail2ban --no-pager -l || true
    journalctl -u fail2ban -n 80 --no-pager || true
    die "Fail2ban is not responding after 20 seconds."
fi

if ! fail2ban-client status sshd; then
    journalctl -u fail2ban -n 80 --no-pager || true
    die "Fail2ban is running, but the SSH jail is not operational."
fi

log "Fail2ban started successfully; SSH jail is active."

# -------------------- 9. Automatic Updates --------------

section "9/11 - Configuring unattended security updates"

cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

systemctl enable --now unattended-upgrades.service ||
    warn "Could not enable unattended-upgrades.service; verify its configuration."

# -------------------- 10. Certbot -----------------------

section "10/11 - Installing Certbot"

apt-get install -y certbot python3-certbot-nginx

certbot --version

# -------------------- 11. Croc --------------------------

section "11/11 - Installing latest Croc release"

CROC_RELEASE="$(
    curl -fsSL https://api.github.com/repos/schollz/croc/releases/latest
)"

CROC_ASSET="$(
    jq -er '
        [
            .assets[]
            | select(.name | test("_amd64\\.deb$"))
            | {name: .name, url: .browser_download_url, digest: .digest}
        ][0]
        | [.name, .url, (.digest // "")]
        | @tsv
    ' <<< "$CROC_RELEASE"
)" || die "Could not find a Croc amd64 Debian package."

IFS=$'\t' read -r CROC_NAME CROC_URL CROC_DIGEST <<< "$CROC_ASSET"

[[ "$CROC_URL" == https://github.com/schollz/croc/releases/download/* ]] ||
    die "Unexpected Croc download URL."

[[ "$CROC_DIGEST" =~ ^sha256:[a-fA-F0-9]{64}$ ]] ||
    die "GitHub did not provide a usable SHA-256 digest for Croc."

curl -fsSL "$CROC_URL" -o "$TMP_DIR/$CROC_NAME"

EXPECTED_SHA="${CROC_DIGEST#sha256:}"
ACTUAL_SHA="$(sha256sum "$TMP_DIR/$CROC_NAME" | awk '{print $1}')"

[[ "${ACTUAL_SHA,,}" == "${EXPECTED_SHA,,}" ]] ||
    die "Croc checksum verification failed."

apt-get install -y "$TMP_DIR/$CROC_NAME"

log "Croc: $(croc --version 2>&1 | head -n 1)"

# -------------------- Final Verification ----------------

section "Installation Summary"

echo
echo "Operating System : $(. /etc/os-release && echo "$PRETTY_NAME")"
echo "Architecture     : $(dpkg --print-architecture)"
echo "Node.js          : $(node --version)"
echo "npm              : $(npm --version)"
echo "Bun              : $(/root/.bun/bin/bun --version)"
echo "PM2              : $(pm2 --version)"
echo "NGINX            : $(nginx -v 2>&1)"
echo "Certbot          : $(certbot --version 2>&1)"
echo "Croc             : $(croc --version 2>&1 | head -n 1)"
echo
echo "NGINX status:"
systemctl is-active nginx || true

echo
echo "Fail2ban status:"
systemctl is-active fail2ban || true

echo
echo "PM2 process list:"
pm2 list

echo
echo "Backup directory: $BACKUP_DIR"
echo
warn "Before production use, verify SSH access, firewall rules, DNS, TLS, backups and monitoring."
warn "Review UFW rules if your server uses custom SSH, application, database or monitoring ports."

section "Provisioning Complete"