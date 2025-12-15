#!/bin/bash

# Native Slave Installer for Ubuntu/Debian
# Run as root

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Native MariaDB Slave Installer ===${NC}"

if [ "$EUID" -ne 0 ]; then 
  echo "Please run as root"
  exit 1
fi

echo -n "Enter Master IP Address: "
read master_ip

echo -n "Enter Replication Username (default: replication_system): "
read rep_user
rep_user=${rep_user:-replication_system}

echo -n "Enter Replication Password (default: Angk4-SA12a&YA): "
read rep_pass
rep_pass=${rep_pass:-Angk4-SA12a&YA}

# Unique Server ID generation
random_id=$(( ( RANDOM % 100 )  + 2 ))
echo -n "Enter Unique Server ID (default: $random_id): "
read server_id
server_id=${server_id:-$random_id}

# 1. OS Detection
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo "Cannot detect OS"
    exit 1
fi

# 2. Install MariaDB
echo -e "${GREEN}[1/4] Installing MariaDB on $OS...${NC}"
if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
    apt-get update
    apt-get install -y mariadb-server
    CONFIG_FILE="/etc/mysql/mariadb.conf.d/50-server.cnf"
elif [[ "$OS" == "rhel" || "$OS" == "centos" || "$OS" == "almalinux" || "$OS" == "rocky" ]]; then
    dnf install -y mariadb-server
    systemctl enable --now mariadb
    CONFIG_FILE="/etc/my.cnf.d/mariadb-server.cnf"
    if [ ! -f "$CONFIG_FILE" ]; then
        CONFIG_FILE="/etc/my.cnf"
    fi
else
    echo "Unsupported OS: $OS"
    exit 1
fi

# 3. Configure
echo -e "${GREEN}[2/4] Configuring Slave Mode (Server ID: $server_id)...${NC}"
cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"

# Bind Address
if grep -q "bind-address" "$CONFIG_FILE"; then
    sed -i 's/bind-address.*/bind-address = 0.0.0.0/' "$CONFIG_FILE"
else
    if grep -q "\[mysqld\]" "$CONFIG_FILE"; then
        sed -i '/\[mysqld\]/a bind-address = 0.0.0.0' "$CONFIG_FILE"
    else
         echo -e "[mysqld]\nbind-address = 0.0.0.0" >> "$CONFIG_FILE"
    fi
fi

# Server ID
if grep -q "server-id" "$CONFIG_FILE"; then
    sed -i "s/^server-id.*/server-id = $server_id/" "$CONFIG_FILE"
else
    if grep -q "\[mysqld\]" "$CONFIG_FILE"; then
        sed -i "/\[mysqld\]/a server-id = $server_id" "$CONFIG_FILE"
    else
         echo -e "server-id = $server_id" >> "$CONFIG_FILE"
    fi
fi

systemctl restart mariadb

# 3. Connection
echo -e "${GREEN}[3/4] Connecting to Master ($master_ip)...${NC}"
mariadb -e "STOP SLAVE;"
mariadb -e "CHANGE MASTER TO MASTER_HOST='$master_ip', MASTER_USER='$rep_user', MASTER_PASSWORD='$rep_pass', MASTER_LOG_FILE='mysql-bin.000003', MASTER_LOG_POS=100;"
# Note: In real production, LOG_FILE/POS should be obtained from Master status or dump. 
# For simplicity in this wizard, we assume a fresh start or GTID could be enabled.
# To handle auto-pos, we'd need GTID. For now, try to start.

mariadb -e "START SLAVE;"

# 4. Verification
echo -e "${GREEN}[4/4] Verification...${NC}"
mariadb -e "SHOW SLAVE STATUS\G"

echo "Slave Setup Complete!"
echo -e "${YELLOW}NOTE: Please allow incoming connections on Port 3306 in your firewall/security group.${NC}"
