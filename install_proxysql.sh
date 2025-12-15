#!/bin/bash

# Native ProxySQL Installer for Ubuntu/Debian
# Run as root

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Native ProxySQL Installer ===${NC}"

if [ "$EUID" -ne 0 ]; then 
  echo "Please run as root"
  exit 1
fi

echo -n "Enter Master IP Address: "
read master_ip

echo -n "Enter Slave IPs (comma separated): "
read slave_list

# 1. OS Detection
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo "Cannot detect OS"
    exit 1
fi

# 2. Install ProxySQL
echo -e "${GREEN}[1/4] Installing ProxySQL on $OS...${NC}"

if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
    apt-get update
    apt-get install -y lsb-release wget gnupg2
    wget -O - 'https://repo.proxysql.com/ProxySQL/repo_pub_key' | apt-key add -
    echo deb https://repo.proxysql.com/ProxySQL/proxysql-2.5.x/$(lsb_release -sc)/ ./ | tee /etc/apt/sources.list.d/proxysql.list
    apt-get update
    apt-get install -y proxysql mysql-client

elif [[ "$OS" == "rhel" || "$OS" == "centos" || "$OS" == "almalinux" || "$OS" == "rocky" ]]; then
    cat <<EOF > /etc/yum.repos.d/proxysql.repo
[proxysql]
name=ProxySQL YUM repo
baseurl=https://repo.proxysql.com/ProxySQL/proxysql-2.5.x/centos/\$releasever
enabled=1
gpgcheck=1
gpgkey=https://repo.proxysql.com/ProxySQL/repo_pub_key
EOF
    dnf install -y proxysql mysql
else 
    echo "Unsupported OS: $OS"
    exit 1
fi

systemctl enable proxysql
systemctl start proxysql

# 2. Configure via Admin Interface
echo -e "${GREEN}[2/4] Configuring Backend Servers...${NC}"

# Wait for startup
sleep 5

# Function to execute Admin SQL
exec_admin() {
    mysql -u admin -padmin -h 127.0.0.1 -P 6032 --prompt "ProxySQLAdmin> " -e "$1"
}

# Add Master
exec_admin "INSERT INTO mysql_servers (hostgroup_id, hostname, port, max_connections) VALUES (10, '$master_ip', 3306, 200);"

# Add Slaves
IFS=',' read -ra SLAVE_IPS <<< "$slave_list"
for ip in "${SLAVE_IPS[@]}"; do
    ip=$(echo $ip | xargs)
    exec_admin "INSERT INTO mysql_servers (hostgroup_id, hostname, port, max_connections) VALUES (20, '$ip', 3306, 200);"
done

exec_admin "LOAD MYSQL SERVERS TO RUNTIME; SAVE MYSQL SERVERS TO DISK;"

# 3. Configure Users
echo -e "${GREEN}[3/4] Configuring Users & Monitor...${NC}"
# Monitor
exec_admin "UPDATE global_variables SET variable_value='monitor' WHERE variable_name='mysql-monitor_username';"
exec_admin "UPDATE global_variables SET variable_value='monitor_password' WHERE variable_name='mysql-monitor_password';"
exec_admin "LOAD MYSQL VARIABLES TO RUNTIME; SAVE MYSQL VARIABLES TO DISK;"

# App Users (default example)
exec_admin "INSERT INTO mysql_users (username, password, default_hostgroup) VALUES ('root', 'root_password', 10);"
exec_admin "INSERT INTO mysql_users (username, password, default_hostgroup) VALUES ('replication_system', 'Angk4-SA12a&YA', 10);"
exec_admin "LOAD MYSQL USERS TO RUNTIME; SAVE MYSQL USERS TO DISK;"

# 4. Configure Rules
echo -e "${GREEN}[4/4] Configuring Query Rules (Read/Write Split)...${NC}"

# Rule 1: SELECT FOR UPDATE -> Master
exec_admin "INSERT INTO mysql_query_rules (rule_id, active, match_digest, destination_hostgroup, apply) VALUES (1, 1, '^SELECT.*FOR UPDATE$', 10, 1);"

# Rule 2: SELECT -> Slave
exec_admin "INSERT INTO mysql_query_rules (rule_id, active, match_digest, destination_hostgroup, apply) VALUES (2, 1, '^SELECT', 20, 1);"

# Rule 3: Default -> Master
exec_admin "INSERT INTO mysql_query_rules (rule_id, active, match_digest, destination_hostgroup, apply) VALUES (3, 1, '.*', 10, 1);"

exec_admin "LOAD MYSQL QUERY RULES TO RUNTIME; SAVE MYSQL QUERY RULES TO DISK;"

echo -e "${GREEN}ProxySQL Setup Complete!${NC}"
echo "Admin Interface: Port 6032"
echo "SQL Interface: Port 6033"
