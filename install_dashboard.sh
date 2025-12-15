#!/bin/bash

# Native Dashboard Installer for Ubuntu/Debian/RHEL
# Run as root

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}=== Native Dashboard Installer ===${NC}"

if [ "$EUID" -ne 0 ]; then 
  echo "Please run as root"
  exit 1
fi

# 1. OS Detection
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo "Cannot detect OS"
    exit 1
fi

# 2. Install Python & Pip
echo -e "${GREEN}[1/5] Installing Python3 and Pip on $OS...${NC}"

if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
    apt-get update
    apt-get install -y python3 python3-pip python3-venv
elif [[ "$OS" == "rhel" || "$OS" == "centos" || "$OS" == "almalinux" || "$OS" == "rocky" ]]; then
    dnf install -y python3 python3-pip
else
    echo "Unsupported OS: $OS"
    exit 1
fi

# 3. Setup Application Directory
echo -e "${GREEN}[2/5] Setting up Application...${NC}"
APP_DIR="/opt/mariadb-cluster-dashboard"
mkdir -p $APP_DIR

# Copy dashboard files (assuming this script is run from the repo root or files are present)
# In a real scenario, we might clone the repo here. 
# For this installer, we assume the 'dashboard' folder is next to this script.
if [ -d "dashboard" ]; then
    cp -r dashboard/* $APP_DIR/
else
    echo -e "${YELLOW}Warning: 'dashboard' directory not found locally. Cloning from GitHub...${NC}"
    git clone https://github.com/karimwafa/mariadb-cluster-multiserver-with-docker.git /tmp/repo
    cp -r /tmp/repo/dashboard/* $APP_DIR/
    rm -rf /tmp/repo
fi

# 4. Install Dependencies
echo -e "${GREEN}[3/5] Installing Python Dependencies...${NC}"
pip3 install -r $APP_DIR/requirements.txt || pip3 install flask pymysql cryptography

# 5. Configure Service
echo -e "${GREEN}[4/5] Configuring Systemd Service...${NC}"

echo -n "Enter Master IP: "
read master_ip
echo -n "Enter Slave 1 IP: "
read slave1_ip
echo -n "Enter Slave 2 IP: "
read slave2_ip
echo -n "Enter Slave 3 IP: "
read slave3_ip
echo -n "Enter ProxySQL IP: "
read proxysql_ip

cat <<EOF > /etc/systemd/system/mariadb-dashboard.service
[Unit]
Description=MariaDB Cluster Dashboard
After=network.target

[Service]
User=root
WorkingDirectory=$APP_DIR
Environment="DB_MASTER_HOST=$master_ip"
Environment="DB_SLAVE1_HOST=$slave1_ip"
Environment="DB_SLAVE2_HOST=$slave2_ip"
Environment="DB_SLAVE3_HOST=$slave3_ip"
Environment="DB_PROXYSQL_HOST=$proxysql_ip"
ExecStart=/usr/bin/python3 app.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable mariadb-dashboard
systemctl restart mariadb-dashboard

echo -e "${GREEN}[5/5] Setup Complete!${NC}"
echo "Dashboard is running on Port 5000."
echo -e "${YELLOW}NOTE: Please allow incoming connections on Port 5000 in your firewall/security group.${NC}"
