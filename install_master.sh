#!/bin/bash

# Native Master Installer for Ubuntu/Debian
# Run as root

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Native MariaDB Master Installer ===${NC}"

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

# 2. Install MariaDB
echo -e "${GREEN}[1/5] Installing MariaDB on $OS...${NC}"

if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
    apt-get update
    apt-get install -y mariadb-server
    CONFIG_FILE="/etc/mysql/mariadb.conf.d/50-server.cnf"
elif [[ "$OS" == "rhel" || "$OS" == "centos" || "$OS" == "almalinux" || "$OS" == "rocky" ]]; then
    dnf install -y mariadb-server
    systemctl enable --now mariadb
    CONFIG_FILE="/etc/my.cnf.d/mariadb-server.cnf"
    # Create config file if not exists (RHEL sometimes uses just /etc/my.cnf)
    if [ ! -f "$CONFIG_FILE" ]; then
        CONFIG_FILE="/etc/my.cnf"
    fi
else
    echo "Unsupported OS: $OS"
    exit 1
fi

# 3. Configure bindings and ID
echo -e "${GREEN}[2/5] Configuring MariaDB...${NC}"
# Backup config
cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"

# Allow remote access (Bind Address)
# Check if bind-address exists
if grep -q "bind-address" "$CONFIG_FILE"; then
    sed -i 's/bind-address.*/bind-address = 0.0.0.0/' "$CONFIG_FILE"
else
    # Append to [mysqld]
    if grep -q "\[mysqld\]" "$CONFIG_FILE"; then
        sed -i '/\[mysqld\]/a bind-address = 0.0.0.0' "$CONFIG_FILE"
    else
         echo -e "[mysqld]\nbind-address = 0.0.0.0" >> "$CONFIG_FILE"
    fi
fi

# Set Server ID and Enable Binlog
# We check if [mysqld] exists, then append or modify
if grep -q "server-id" "$CONFIG_FILE"; then
    sed -i 's/^server-id.*/server-id = 1/' "$CONFIG_FILE"
else
    # Insert under [mysqld] section if possible, or append
    if grep -q "\[mysqld\]" "$CONFIG_FILE"; then
        sed -i '/\[mysqld\]/a server-id = 1\nlog_bin = mysql-bin' "$CONFIG_FILE"
    else
        echo -e "server-id = 1\nlog_bin = mysql-bin" >> "$CONFIG_FILE"
    fi
fi

# Ensure log_bin is active (sometimes commented out by default)
sed -i 's/#log_bin/log_bin/' "$CONFIG_FILE"

# Restart Service
systemctl restart mariadb

# 3. Security Check
echo -e "${GREEN}[3/5] Securing Installation...${NC}"
# Automating mysql_secure_installation via SQL
mariadb -e "DELETE FROM mysql.user WHERE User='';"
mariadb -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
mariadb -e "DROP DATABASE IF EXISTS test;"
mariadb -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
mariadb -e "FLUSH PRIVILEGES;"

# 4. Create Replication User
echo -e "${GREEN}[4/5] Creating Replication Credentials...${NC}"
echo -n "Enter Replication Username (default: replication_system): "
read rep_user
rep_user=${rep_user:-replication_system}

echo -n "Enter Replication Password (default: Angk4-SA12a&YA): "
read rep_pass
rep_pass=${rep_pass:-Angk4-SA12a&YA}

mariadb -e "CREATE USER '$rep_user'@'%' IDENTIFIED BY '$rep_pass';"
mariadb -e "GRANT REPLICATION SLAVE ON *.* TO '$rep_user'@'%';"
mariadb -e "FLUSH PRIVILEGES;"

echo -e "${GREEN}[5/5] Setup Complete!${NC}"
echo "Master is running on Port 3306."
echo -e "${YELLOW}NOTE: Please allow incoming connections on Port 3306 in your firewall/security group.${NC}"
