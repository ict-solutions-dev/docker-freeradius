# 🌐 FreeRADIUS Server Docker Image

![Docker](https://img.shields.io/badge/docker-%230db7ed.svg?style=for-the-badge&logo=docker&logoColor=white)
![Ubuntu](https://img.shields.io/badge/Ubuntu-E95420?style=for-the-badge&logo=ubuntu&logoColor=white)
![FreeRADIUS](https://img.shields.io/badge/FreeRADIUS-3.2-blue?style=for-the-badge)
![MySQL](https://img.shields.io/badge/mysql-%2300f.svg?style=for-the-badge&logo=mysql&logoColor=white)

FreeRADIUS Docker container based on **Ubuntu 22.04.5 LTS**, specifically optimized for Internet Service Providers (ISPs).

> [!NOTE]
> This container is production-ready and includes advanced features like CoA relay, SQL read-only mode, and real-time debugging capabilities.

## 📋 Table of Contents

- [🚀 Quick Start](#-quick-start)
- [⚙️ Environment Variables](#️-environment-variables)
- [🔄 Configuration Reloading API](#-configuration-reloading-api)
- [🗄️ Database Configuration](#️-database-configuration)
- [📊 Status Server](#-status-server)
- [🔄 CoA Relay](#-coa-relay)
- [🛡️ Auth Reject Logging (fail2ban)](#️-auth-reject-logging-fail2ban-integration)
- [🛠️ Debugging](#️-debugging)
- [📝 Examples](#-examples)

## 🚀 Quick Start

```bash
# Basic setup with MySQL
docker run -d \
  -p 1812:1812/udp \
  -p 1813:1813/udp \
  -e SQL_ENABLE=true \
  -e MYSQL_HOST=mysql-server \
  -e MYSQL_PASSWORD=your-password \
  ghcr.io/ict-solutions-dev/freeradius:edge-freeradius3.2.8
```

> [!TIP]
> For production deployments, always use specific version tags instead of `edge`.

## ⚙️ Environment Variables

### 🗄️ Core Database Settings

| Variable | Default | Type | Description |
|----------|---------|------|-------------|
| `SQL_ENABLE` | `false` | boolean | Enable MySQL support |
| `SQL_READ_ONLY` | `false` | boolean | Enable read-only mode (no accounting/post-auth) |
| `MYSQL_INIT` | `false` | boolean | Initialize MySQL schema on first run |
| `MYSQL_HOST` | `mysql` | string | MySQL server hostname |
| `MYSQL_PORT` | `3306` | integer | MySQL server port |
| `MYSQL_DATABASE` | `radius` | string | MySQL database name |
| `MYSQL_USER` | `radius` | string | MySQL username |
| `MYSQL_PASSWORD` | `radpass` | string | MySQL user password |

> [!WARNING]
> Always use strong passwords for `MYSQL_PASSWORD` in production environments.

### 🔄 Read-Only Database Settings

> [!INFO]
> When `SQL_ENABLE_RO=true` and `MYSQL_HOST_RO` is configured, the container automatically creates a separate `sql_ro` module in `mods-available/` and enables it in `mods-enabled/`.

| Variable | Default | Type | Description |
|----------|---------|------|-------------|
| `SQL_ENABLE_RO` | `false` | boolean | Enable secondary read-only MySQL support |
| `MYSQL_HOST_RO` | `mysql-ro` | string | Read-only MySQL server hostname |
| `MYSQL_PORT_RO` | `3306` | integer | Read-only MySQL server port |
| `MYSQL_DATABASE_RO` | `radius_ro` | string | Read-only MySQL database name |
| `MYSQL_USER_RO` | `radius_ro` | string | Read-only MySQL username |
| `MYSQL_PASSWORD_RO` | `radpass_ro` | string | Read-only MySQL user password |

#### 🔧 Automatic sql_ro Module Creation

When enabled, the following automated configuration occurs:

1. **📁 Module Creation**: Copies `sql` to `sql_ro` in `mods-available/`
2. **🏷️ Module Naming**: Changes module declaration from `sql {` to `sql_ro {`
3. **🗄️ Database Configuration**: Sets MySQL dialect and driver
4. **🔒 Security Setup**: Disables TLS configuration for simplified setup
5. **🔗 Connection Parameters**: Configures read-only database connection
6. **👥 Client Reading**: Optionally enables NAS client reading from RO database
7. **✅ Module Activation**: Creates symbolic link in `mods-enabled/`

#### 📋 Configuration Details

**Database Connection Setup:**
```diff
# Connection parameters are automatically configured
-    #server = "localhost"
+    server = "{MYSQL_HOST_RO}"
-    #port = 3306
+    port = "{MYSQL_PORT_RO}"
-    #login = "radius"
+    login = "{MYSQL_USER_RO}"
-    #password = "radpass"
+    password = "{MYSQL_PASSWORD_RO}"
-    radius_db="radius"
+    radius_db="{MYSQL_DATABASE_RO}"
```

**TLS Configuration (Disabled):**
```diff
# TLS is automatically disabled for simplified setup
-    ca_file = "/etc/ssl/certs/my_ca.crt"
+    # ca_file = "/etc/ssl/certs/my_ca.crt"
-    tls_required = yes
+    tls_required = no
```

**Client Reading (Optional):**
```bash
# Enable reading RADIUS clients from read-only database
SQL_READ_CLIENTS_RO=true
```

```diff
# When SQL_READ_CLIENTS_RO=true
-    #read_clients = yes
+    read_clients = yes
```

#### 🎯 Use Cases for sql_ro Module

- **📊 Read-Only Replicas**: Connect to MySQL read replicas for load distribution
- **🔍 Monitoring Systems**: Separate monitoring queries from production writes
- **🌍 Geographic Distribution**: Use local read replicas in different regions
- **⚖️ Load Balancing**: Distribute read operations across multiple database instances
- **🔒 Security Segregation**: Limit write access while maintaining read capabilities

#### 💡 Example Configuration

```bash
# Enable primary SQL with write access
SQL_ENABLE=true
MYSQL_HOST=mysql-primary
MYSQL_USER=radius_write
MYSQL_PASSWORD=write_password

# Enable secondary read-only SQL
SQL_ENABLE_RO=true
MYSQL_HOST_RO=mysql-replica
MYSQL_USER_RO=radius_readonly
MYSQL_PASSWORD_RO=readonly_password
MYSQL_DATABASE_RO=radius_replica

# Optional: Read NAS clients from read-only database
SQL_READ_CLIENTS_RO=true

# Use read-only module for authorize section
SQL_ENABLE_RO_AUTH=true
```

> [!WARNING]
> Ensure the read-only database user has SELECT permissions on required tables (`radcheck`, `radreply`, `radgroupcheck`, `radgroupreply`, `radusergroup`, and optionally `nas`).

> [!TIP]
> The `sql_ro` module can be used alongside the primary `sql` module, allowing you to route different operations to different database instances for optimal performance.

### 🚀 Advanced Features

| Variable | Default | Type | Description |
|----------|---------|------|-------------|
| `SQL_COUNTER_ENABLE` | `false` | boolean | Enable sqlcounter module |
| `SQL_READ_CLIENTS` | `false` | boolean | Read RADIUS clients from database ('nas' table) |
| `SQL_READ_CLIENTS_RO` | `false` | boolean | Read RADIUS clients from read-only database |
| `SQL_ENABLE_RO_AUTH` | `false` | boolean | Use sql_ro for authorize section |
| `SQL_IPPOOL_ENABLE` | `false` | boolean | Enable sqlippool module |
| `CUSTOM_MYSQL_QUERIES_POST_AUTH` | `false` | boolean | Enable custom post-auth SQL queries |
| `CUSTOM_MYSQL_QUERIES_POST_AUTH_EXTENDED` | `false` | boolean | Add Calling/Called-Station-Id to post-auth logging |
| `AUTH_REJECT_LOG` | `false` | boolean | Enable auth reject file logging for fail2ban |
| `AUTH_REJECT_LOG_PATH` | `/var/log/freeradius/auth-reject.log` | string | Auth reject log file path |

### 🔧 Client Management

| Variable | Default | Type | Description |
|----------|---------|------|-------------|
| `DEFAULT_CLIENT_ENABLE` | `false` | boolean | Add default RADIUS client for container subnet |
| `DEFAULT_CLIENT_SECRET` | `testing123` | string | Secret for default RADIUS client |
| `DEFAULT_CLIENT_SHORTNAME` | `DOCKER NET` | string | Short name for default RADIUS client |

### 🐛 Debugging & Monitoring

| Variable | Default | Type | Description |
|----------|---------|------|-------------|
| `RADDEBUG_ENABLE` | `false` | boolean | Enable raddebug control socket |
| `STATUS_ENABLE` | `false` | boolean | Enable status virtual server |
| `STATUS_INTERFACE` | `eth0` | string | Interface for status server |
| `STATUS_USE_ALL_INTERFACES` | `false` | boolean | Listen on all interfaces (0.0.0.0) |
| `STATUS_CLIENT` | `admin` | string | Status client name |
| `STATUS_SECRET` | `adminsecret` | string | Status client secret |

### 🔄 CoA Relay Configuration

| Variable | Default | Type | Description |
|----------|---------|------|-------------|
| `COA_RELAY_ENABLE` | `false` | boolean | Enable CoA relay |
| `COA_RELAY_INTERFACE` | `eth0` | string | Interface for CoA relay |
| `COA_RELAY_USE_ALL_INTERFACES` | `false` | boolean | Listen on all interfaces (0.0.0.0) |
| `COA_RELAY_DISABLE_LEGACY_ATTRIBUTES` | `false` | boolean | Disable Event-Timestamp and Message-Authenticator |
| `COA_RELAY_PACKET_DST_PORT` | `3799` | integer | CoA relay destination port |
| `COA_RELAY_NAS_IP_n` | - | string | NAS IP for CoA relay (n = 1,2,...) |
| `COA_RELAY_NAS_PORT_n` | `3799` | integer | NAS port for CoA relay (n = 1,2,...) |
| `COA_RELAY_NAS_SECRET_n` | - | string | NAS secret for CoA relay (n = 1,2,...) |

### 🎛️ Control API

| Variable | Default | Type | Description |
|----------|---------|------|-------------|
| `CONTROL_ENABLE` | `false` | boolean | Enable control API endpoint |
| `CONTROL_PORT` | `18120` | integer | TCP port for control server |
| `CONTROL_TOKEN` | `secret123` | string | Authentication token for control server |

### 🔧 PPP & EAP Settings

| Variable | Default | Type | Description |
|----------|---------|------|-------------|
| `DISABLE_PPP_VJ_COMPRESSION` | `false` | boolean | Disable PPP Van Jacobson TCP/IP header compression |
| `EAP_USE_TUNNELED_REPLY` | `false` | boolean | Enable EAP tunneled reply |

---

## 🔄 Configuration Reloading API

> [!IMPORTANT]
> The REST API allows for runtime configuration reloading without container restart.

### 📡 API Specification

- **Endpoint**: `/restart`
- **Method**: `POST`
- **Port**: `18120` (configurable via `CONTROL_PORT`)
- **Authentication**: Bearer token required

### 🔐 Authentication

```http
Authorization: Bearer your-control-token
```

### 📊 Response Codes

| Status | Description |
|--------|-------------|
| 🟢 `200` | Configuration successfully reloaded |
| 🔴 `401` | Invalid authentication token |
| 🟡 `405` | Method not allowed (only POST supported) |
| 🔴 `500` | Internal server error |

### 💡 Example Usage

**Using curl:**
```bash
curl -X POST http://localhost:18120/restart \
  -H "Authorization: Bearer testing123"
```

**Using httpie:**
```bash
http POST localhost:18120/restart \
  "Authorization: Bearer testing123"
```

### ⚙️ Reload Process

1. ✅ Validates authentication token
2. 🔄 Sends SIGHUP to FreeRADIUS process
3. 📤 Returns success/failure response

> [!CAUTION]
> Ensure the control token is kept secure and not exposed in logs or environment variable dumps.

---

## 🗄️ Database Configuration

### 📖 Read-Only Mode (`SQL_READ_ONLY = true`)

> [!NOTE]
> Read-only mode is perfect for monitoring setups, load balancing, and security-conscious deployments.

When enabled, FreeRADIUS operates in read-only mode:

- ✅ **Authentication queries**: Enabled (SELECT operations)
- ✅ **NAS clients**: Read from database (`nas` table)
- ❌ **Accounting**: Disabled (no INSERT into `radacct`)
- ❌ **Post-auth logging**: Disabled (no INSERT into `radpostauth`)

**Use cases:**
- 📊 **Monitoring setups**: Authentication without logging
- ⚖️ **Load balancing**: Multiple read-only instances
- 🔒 **Security**: Prevent accidental data modification

```bash
# Enable SQL with read-only access
SQL_ENABLE=true
SQL_READ_ONLY=true
MYSQL_HOST=mysql-server
MYSQL_USER=radius_readonly
MYSQL_PASSWORD=readonly_pass
```

> [!WARNING]
> When `SQL_READ_ONLY=true`, the `SQL_COUNTER_ENABLE` and `SQL_IPPOOL_ENABLE` options are ignored as they require write access.

### 👥 Default Client Management

Control automatic RADIUS client creation:

```bash
# Enable automatic addition of default client
DEFAULT_CLIENT_ENABLE=true
DEFAULT_CLIENT_SECRET=mysecret123
DEFAULT_CLIENT_SHORTNAME="K8S CLUSTER"
```

**Environment-specific examples:**
- 🐳 **Docker Compose**: `DEFAULT_CLIENT_SHORTNAME="DOCKER NET"`
- ☸️ **Kubernetes**: `DEFAULT_CLIENT_SHORTNAME="K8S CLUSTER"`
- 🖥️ **Host Network**: `DEFAULT_CLIENT_SHORTNAME="HOST NET"`

> [!TIP]
> If `DEFAULT_CLIENT_ENABLE=false`, you must manage clients manually in the database.

---

## 📊 Status Server

Enable monitoring and statistics collection:

```bash
STATUS_ENABLE=true
STATUS_INTERFACE=eth0
STATUS_CLIENT=exporter
STATUS_SECRET=adminsecret1
```

### 🔧 Configuration Changes

When `STATUS_ENABLE=true`, the following configuration is applied:

```diff
server status {
        listen {
                type = status
-               ipaddr = 127.0.0.1
+               ipaddr = {$RADIUS_CONTAINER_IP}
                port = 18121
        }

        #
        #  We recommend that you list ONLY management clients here.
        #  i.e. NOT your NASes or Access Points, and for an ISP,
        #  DEFINITELY not any RADIUS servers that are proxying packets
        #  to you.
        #
        #  If you do NOT list a client here, then any client that is
        #  globally defined (i.e. all of them) will be able to query
        #  these statistics.
        #
        #  Do you really want your partners seeing the internal details
        #  of what your RADIUS server is doing?
        #
-       client admin {
+       client {$STATUS_CLIENT} {
-               ipaddr = 127.0.0.1
+               ipaddr = 0.0.0.0
-               secret = adminsecret
+               secret = {$STATUS_SECRET}
        }

        #
        #  Simple authorize section.  The "Autz-Type Status-Server"
        #  section will work here, too.  See "raddb/sites-available/default".
        authorize {
                ok

                # respond to the Status-Server request.
                Autz-Type Status-Server {
                        ok
                }
        }
}
```

> [!SECURITY]
> List only management clients for status queries. Avoid exposing internal statistics to NAS devices or partners.

---

## 🔄 CoA Relay

> [!NOTE]
> CoA (Change of Authorization) relay simplifies session management across multiple NAS devices.

### 🎯 Purpose

The CoA relay virtual server:
- 📥 Receives CoA/Disconnect requests with minimal identification
- 🔍 Looks up full session data in the database
- 📤 Forwards complete requests to appropriate NAS devices

### 🔄 Process Flow

1. **Request Reception**: CoA/Disconnect-Request received
2. **Database Lookup**: Search `radacct` table for active sessions
3. **Session Identification**: Find NAS and session details
4. **Request Forwarding**: Send complete request to target NAS

### 💡 Benefits

- 🎯 **Simplified Scripting**: Single request to FreeRADIUS handles multiple NAS devices
- 🔍 **Auto-Discovery**: Automatic session lookup by username
- 🌐 **Multi-NAS Support**: Route requests to correct NAS automatically

### 📝 Examples

**Disconnect specific session:**
```bash
echo 'Acct-Session-Id = "769df3 312343"' | \
    radclient 127.0.0.1 disconnect testing123
```

**CoA update for all user sessions:**
```bash
cat <<EOF | radclient 127.0.0.1 coa testing123
User-Name = bob
Cisco-AVPair = "subscriber:sub-qos-policy-out=q_out_uncapped"
EOF
```

> [!IMPORTANT]
> Configure the detail writer module in `mods-enabled` for CoA relay to function properly.

---

## 🛠️ Debugging

### 🐛 Enable Debugging

```bash
# Enable raddebug support
RADDEBUG_ENABLE=true
```

### 🔍 Usage Examples

```bash
# Start debug capture (10 seconds default)
raddebug

# Extended debug capture (30 seconds)
raddebug -t 30

# Capture to file
raddebug > /var/log/freeradius/debug/radius_debug.log
```

> [!TIP]
> Debug output is displayed in real-time and automatically cleaned up when finished.

---

## 🚀 Advanced Features

### 🔧 PPP Configuration

Disable Van Jacobson compression for Cisco ASR BRAS compatibility:

```bash
DISABLE_PPP_VJ_COMPRESSION=true
```

**Effect:**
```diff
DEFAULT Framed-Protocol == PPP
-        Framed-Protocol = PPP,
-        Framed-Compression = Van-Jacobson-TCP-IP
+        Framed-Protocol = PPP
+        #Framed-Compression = Van-Jacobson-TCP-IP
```

### 📊 Custom Post-Auth Queries

Extend the MySQL schema for enhanced logging:

```bash
CUSTOM_MYSQL_QUERIES_POST_AUTH=true
```

> [!INFO]
> This automatically adds `reply_message` and `nasipaddress` columns to the `radpostauth` table and updates the query configuration. Schema migrations run on every container start (safe to re-run).

#### 🔍 Extended Post-Auth Logging

Log `Calling-Station-Id` (client IP) and `Called-Station-Id` (gateway IP) for VPN/AnyConnect environments:

```bash
CUSTOM_MYSQL_QUERIES_POST_AUTH=true
CUSTOM_MYSQL_QUERIES_POST_AUTH_EXTENDED=true
```

This adds `callingstationid` and `calledstationid` columns to the `radpostauth` table. Toggle on/off without deleting the init lock — query configuration is applied on every container start.

| Variable | Default | Type | Description |
|----------|---------|------|-------------|
| `CUSTOM_MYSQL_QUERIES_POST_AUTH` | `false` | boolean | Enable custom post-auth queries (reply_message, nasipaddress) |
| `CUSTOM_MYSQL_QUERIES_POST_AUTH_EXTENDED` | `false` | boolean | Add Calling-Station-Id and Called-Station-Id logging |

---

### 🛡️ Auth Reject Logging (fail2ban Integration)

Log `Access-Reject` events to a file for consumption by fail2ban on the host VM. This enables automatic IP blocking of brute force attackers via iptables/nftables.

```bash
AUTH_REJECT_LOG=true
```

| Variable | Default | Type | Description |
|----------|---------|------|-------------|
| `AUTH_REJECT_LOG` | `false` | boolean | Enable auth reject file logging |
| `AUTH_REJECT_LOG_PATH` | `/var/log/freeradius/auth-reject.log` | string | Log file path |

> [!NOTE]
> Only requests with a `Calling-Station-Id` attribute are logged. Internal requests without a client IP are skipped.

**Log format:**
```
2026-04-02 10:06:44 : Auth-Reject : user=admin calling-station-id=1.2.3.4 called-station-id=10.0.0.1
```

#### 🔧 Docker Swarm Setup

Add a named volume in your stack compose for the FreeRADIUS service:

```yaml
services:
  freeradius:
    environment:
      AUTH_REJECT_LOG: "true"
    volumes:
      - freeradius_auth_logs:/var/log/freeradius

volumes:
  freeradius_auth_logs:
    driver: local
```

Find the volume path on the host VM:

```bash
docker volume inspect <stack>_freeradius_auth_logs --format '{{.Mountpoint}}'
# Example output: /var/lib/docker/volumes/radius_auth_freeradius_auth_logs/_data
```

#### 🔧 fail2ban Configuration

Install fail2ban on the host VM:

```bash
apt install fail2ban
```

**Filter** — `/etc/fail2ban/filter.d/freeradius-reject.conf`:

```ini
[Definition]
failregex = ^.* : Auth-Reject : user=.* calling-station-id=<HOST> called-station-id=.*$
ignoreregex =
```

**Jail** — `/etc/fail2ban/jail.d/freeradius-reject.conf`:

```ini
[freeradius-reject]
enabled = true
filter = freeradius-reject
logpath = /var/lib/docker/volumes/<stack>_freeradius_auth_logs/_data/auth-reject.log
banaction = nftables[type=allports]
maxretry = 5
findtime = 600
bantime = 3600
```

| Parameter | Value | Description |
|-----------|-------|-------------|
| `maxretry` | `5` | Block after 5 failed attempts |
| `findtime` | `600` | Within a 10-minute window |
| `bantime` | `3600` | Ban for 1 hour |

```bash
systemctl restart fail2ban
fail2ban-client status freeradius-reject
```

#### 📊 fail2ban Monitoring (Prometheus + Grafana)

Use [fail2ban-prometheus-exporter](https://github.com/hectorjsmith/fail2ban-prometheus-exporter) to expose metrics:

```bash
# Install and run on the host VM
./fail2ban-prometheus-exporter --web.listen-address=":9191"
```

Add to your Prometheus scrape config:

```yaml
scrape_configs:
  - job_name: fail2ban
    static_configs:
      - targets: ['<vm-ip>:9191']
```

A ready-made Grafana dashboard is available at [Grafana Dashboard #17580](https://grafana.com/grafana/dashboards/17580).

---

## 📝 Examples

### 🔐 Authentication Test

```bash
echo "User-Name = pppoe@example.com,User-Password = simulate" | \
    radclient -x -s '127.0.0.1' auth testing123
```

### 🔌 Disconnect User

```bash
echo "User-Name = pppoe@example.com" | \
    radclient -x -s '127.0.0.1' disconnect testing123
```

### 🔄 CoA Update

```bash
echo "User-Name = pppoe@example.com,Framed-IP-Address = 100.64.0.107" | \
    radclient -x -s '127.0.0.1' coa testing123
```

### 🏷️ Cisco Service Info

```bash
echo 'User-Name = "pppoe@example.com",Cisco-Service-Info = "QD;1048576000;196608000;393216000;U;104857600;19660800;39321600"' | \
    radclient -x -s '127.0.0.1' coa testing123
```

---

## 📚 Additional Resources

> [!TIP]
> - 📖 [FreeRADIUS Documentation](https://freeradius.org/documentation/)
> - 🐳 [Docker Best Practices](https://docs.docker.com/develop/dev-best-practices/)
> - 🔒 [RADIUS Security Guidelines](https://freeradius.org/security/)

---

*Built with ❤️ for ISP environments*
