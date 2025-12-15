# MariaDB Cluster (Native / On-Premise)

This folder contains scripts to install the cluster components directly on **Ubuntu/Debian** servers without Docker.

## Prerequisites
- **Root Access**: You must run scripts as `root`.
- **Operating System**: Ubuntu 20.04/22.04 LTS or Debian 11/12.
- **Network**: All servers must be able to ping each other. Open Ports 3306, 6032, 6033.

## Installation Steps

### 1. Master Server
Run this on your primary server:
```bash
./install_master.sh
```
- It will install MariaDB Server.
- It will ask you to create a **Replication Username & Password**.
- Note the IP Address of this server.

### 2. Slave Server(s)
Run this on your secondary servers:
```bash
./install_slave.sh
```
- It will install MariaDB Server.
- Enter the **Master IP**.
- Enter the **Replication Credentials** you created in Step 1.

### 3. ProxySQL (Load Balancer)
Run this on the server acting as the gateway:
```bash
./install_proxysql.sh
```
- Enter **Master IP** and **Slave IPs**.
- It will install ProxySQL and configure Read/Write splitting automatically.

### 4. Dashboard (Monitoring)
Run this on any server (can be same as ProxySQL):
```bash
./install_dashboard.sh
```
- It will install Python and Flask.
- It will aks for **All Node IPs** to configure connectivity.
- Access via browser: `http://<SERVER_IP>:5000`

## Firewall Tips
If using `ufw` or other firewalls, allow these ports:
- **3306**: Database (Master/Slaves)
- **6033**: ProxySQL (SQL Traffic)
- **6032**: ProxySQL (Admin)
- **5000**: Dashboard Web UI
