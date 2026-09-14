#!/usr/bin/env bash
# ==============================================================================
# SuccessFactors Learning Center - Ubuntu Automated Deployment Script
# ==============================================================================
# Usage:
#   1. Upload your exported zip file (e.g., app.zip) to the Ubuntu server.
#   2. Run:
#        chmod +x deploy.sh
#        sudo ./deploy.sh app.zip
#
# If run inside the already-extracted directory:
#        sudo ./deploy.sh
# ==============================================================================

set -e

ZIP_FILE="$1"
APP_DIR="/var/www/successfactors-learning"
PORT="80"

echo "============================================================"
echo " Starting Automated Deployment for SuccessFactors Learning "
echo "============================================================"

# 1. Ensure script is run with root/sudo privileges
if [ "$EUID" -ne 0 ]; then
  echo "[ERROR] Please run this script with sudo: sudo ./deploy.sh [zip_file]"
  exit 1
fi

# 2. Install essential dependencies
echo "--> Updating system packages..."
apt-get update -y

echo "--> Installing curl, unzip, and web tools..."
apt-get install -y curl unzip nginx build-essential

# 3. Check and install Node.js 20 LTS if missing
if ! command -v node &> /dev/null || [ "$(node -v | cut -d'.' -f1 | tr -d 'v')" -lt 20 ]; then
  echo "--> Installing Node.js 20.x LTS via NodeSource..."
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt-get install -y nodejs
else
  echo "--> Node.js $(node -v) is already installed."
fi

echo "--> Node: $(node -v), npm: $(npm -v)"

# 4. Prepare application directory and unpack ZIP if provided
mkdir -p "$APP_DIR"

if [ -n "$ZIP_FILE" ] && [ -f "$ZIP_FILE" ]; then
  echo "--> Unpacking $ZIP_FILE into $APP_DIR..."
  unzip -o -q "$ZIP_FILE" -d "$APP_DIR"
elif [ -f "./package.json" ]; then
  echo "--> Found package.json in current directory. Copying files to $APP_DIR..."
  cp -r ./* "$APP_DIR/" 2>/dev/null || true
  cp -r ./.* "$APP_DIR/" 2>/dev/null || true
else
  echo "[ERROR] No zip file provided and not inside an extracted project directory."
  echo "Usage: sudo ./deploy.sh <path-to-app.zip>"
  exit 1
fi

cd "$APP_DIR"

# 5. Install npm dependencies and build the app
echo "--> Installing npm dependencies..."
npm install --silent

echo "--> Compiling production build (dist/)..."
npm run build

if [ ! -d "$APP_DIR/dist" ]; then
  echo "[ERROR] Build failed: dist/ directory was not created."
  exit 1
fi

# Set appropriate permissions
chown -R www-data:www-data "$APP_DIR"
chmod -R 755 "$APP_DIR"

# 6. Configure Nginx with SPA routing support
echo "--> Configuring Nginx reverse proxy & static file server..."

cat > /etc/nginx/sites-available/successfactors-learning << 'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    root /var/www/successfactors-learning/dist;
    index index.html;

    # SPA routing fallback: route all paths to index.html
    location / {
        try_files $uri $uri/ /index.html;
    }

    # Cache static assets
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, no-transform";
    }

    # Gzip Compression
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml application/json application/javascript application/image/svg+xml font/woff2;
}
EOF

# Enable the site and remove default
ln -sf /etc/nginx/sites-available/successfactors-learning /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Test Nginx configuration
nginx -t

echo "--> Reloading Nginx service..."
systemctl restart nginx
systemctl enable nginx

# 7. Configure UFW Firewall if active
if command -v ufw &> /dev/null && ufw status | grep -q "active"; then
  echo "--> Permitting HTTP traffic on port 80..."
  ufw allow 80/tcp
  ufw allow 'Nginx Full'
fi

# 8. Retrieve server IP for convenience
SERVER_IP=$(curl -s -4 ifconfig.me || hostname -I | awk '{print $1}')

echo "============================================================"
echo " DEPLOYMENT COMPLETED SUCCESSFULLY! "
echo "============================================================"
echo " Your SuccessFactors Learning Center is live at:"
echo "   http://${SERVER_IP}/"
echo ""
echo " Application Root: $APP_DIR"
echo " Nginx Config:     /etc/nginx/sites-available/successfactors-learning"
echo "============================================================"
