# Security Hardening Guide — MinervaDB Server for ClickHouse

Comprehensive security hardening, RBAC, TLS configuration, and audit logging for production ClickHouse deployments.

---

## Table of Contents

1. [Authentication](#authentication)
2. [Role-Based Access Control (RBAC)](#role-based-access-control-rbac)
3. [Row-Level and Column-Level Security](#row-level-and-column-level-security)
4. [TLS / mTLS Configuration](#tls--mtls-configuration)
5. [Network Security](#network-security)
6. [Audit Logging](#audit-logging)
7. [Secrets Management](#secrets-management)
8. [Security Checklist](#security-checklist)

---

## Authentication

### User Management

```sql
-- Create users with strong passwords
CREATE USER analytics_user
  IDENTIFIED WITH sha256_password BY 'StrongP@ssw0rd!'
  HOST IP '10.0.0.0/8', '172.16.0.0/12'
  DEFAULT ROLE analytics_role
  SETTINGS max_memory_usage = 32212254720,
           max_execution_time = 300,
           readonly = 1;

-- Create service accounts
CREATE USER kafka_writer
  IDENTIFIED WITH sha256_password BY 'kafka_secret'
  HOST IP '10.0.1.0/24';

CREATE USER grafana_reader
  IDENTIFIED WITH sha256_password BY 'grafana_secret'
  HOST IP '10.0.2.50';

-- List users
SELECT name, host_ip, host_names, default_roles_all, default_database
FROM system.users;
```

### LDAP Authentication

```xml
<!-- config.d/ldap.xml -->
<clickhouse>
  <ldap_servers>
    <corp_ldap>
      <host>ldap.company.com</host>
      <port>636</port>
      <bind_dn>cn={user_name},ou=people,dc=company,dc=com</bind_dn>
      <tls_enable>yes</tls_enable>
      <tls_minimum_protocol_version>tls1.2</tls_minimum_protocol_version>
      <tls_require_cert>demand</tls_require_cert>
      <tls_ca_cert_file>/etc/ssl/certs/ldap-ca.crt</tls_ca_cert_file>
      <search_filter>(&amp;(objectClass=user)(sAMAccountName={user_name}))</search_filter>
    </corp_ldap>
  </ldap_servers>

  <users>
    <ldap_user>
      <ldap_server>corp_ldap</ldap_server>
      <roles>
        <analytics_role/>
      </roles>
    </ldap_user>
  </users>
</clickhouse>
```

### Password Policies

```xml
<!-- users.d/00-default-profile.xml -->
<clickhouse>
  <users>
    <default>
      <!-- Disable default user in production -->
      <password></password>
      <networks>
        <ip>::1</ip>      <!-- localhost only -->
        <ip>127.0.0.1</ip>
      </networks>
      <profile>readonly</profile>
      <quota>default</quota>
    </default>
  </users>
</clickhouse>
```

---

## Role-Based Access Control (RBAC)

### Role Hierarchy

```sql
-- Create base roles
CREATE ROLE read_only;
CREATE ROLE analytics_role;
CREATE ROLE data_engineer_role;
CREATE ROLE dba_role;
CREATE ROLE admin_role;

-- Grant permissions to read_only
GRANT SELECT ON *.* TO read_only;

-- Analytics role (read + some system tables)
GRANT read_only TO analytics_role;
GRANT SELECT ON system.query_log TO analytics_role;
GRANT SELECT ON system.processes TO analytics_role;

-- Data engineer (read + write specific databases)
GRANT analytics_role TO data_engineer_role;
GRANT INSERT ON analytics.* TO data_engineer_role;
GRANT CREATE TABLE ON analytics.* TO data_engineer_role;
GRANT ALTER TABLE ON analytics.* TO data_engineer_role;
GRANT DROP TABLE ON analytics.* TO data_engineer_role;

-- DBA role (full access except system modification)
GRANT data_engineer_role TO dba_role;
GRANT INSERT ON *.* TO dba_role;
GRANT CREATE ON *.* TO dba_role;
GRANT ALTER ON *.* TO dba_role;
GRANT DROP ON *.* TO dba_role;
GRANT SYSTEM ON *.* TO dba_role;

-- Admin role (everything)
GRANT dba_role TO admin_role;
GRANT WITH GRANT OPTION ON *.* TO admin_role;
GRANT CREATE USER ON *.* TO admin_role;
GRANT CREATE ROLE ON *.* TO admin_role;
GRANT ALTER USER ON *.* TO admin_role;
GRANT DROP USER ON *.* TO admin_role;
GRANT DROP ROLE ON *.* TO admin_role;

-- Assign roles to users
GRANT analytics_role TO analytics_user;
GRANT data_engineer_role TO etl_user;
GRANT dba_role TO ops_user;
```

### Verify Grants

```sql
-- Check grants for a user
SHOW GRANTS FOR analytics_user;

-- Check effective privileges
SELECT * FROM system.grants WHERE user_name = 'analytics_user';

-- Check role membership
SELECT * FROM system.role_grants WHERE user_name = 'analytics_user';
```

---

## Row-Level and Column-Level Security

### Row Policies (Row-Level Security)

```sql
-- Restrict users to their own tenant data
CREATE ROW POLICY tenant_isolation ON mydb.events
  USING tenant_id = currentUser()
  AS PERMISSIVE FOR SELECT
  TO analytics_role;

-- Date-based restriction (only recent data)
CREATE ROW POLICY recent_data_only ON mydb.events
  USING event_date >= today() - 90
  AS PERMISSIVE FOR SELECT
  TO analytics_role;

-- Compliance: hide PII for non-privileged users
CREATE ROW POLICY no_pii_filter ON mydb.users
  USING is_deleted = 0
  AS PERMISSIVE FOR SELECT
  TO analytics_role;

-- Verify policies
SELECT * FROM system.row_policies;
```

### Column-Level Grants

```sql
-- Grant access to specific columns only (mask sensitive columns)
GRANT SELECT(user_id, event_type, event_date, value)
  ON mydb.events TO analytics_role;

-- Do NOT grant access to: email, ip_address, phone_number, ssn columns

-- Verify column grants
SELECT * FROM system.column_grants WHERE user_name = 'analytics_user';
```

---

## TLS / mTLS Configuration

### Server TLS Setup

```bash
# Generate CA certificate
openssl genrsa -out ca-key.pem 4096
openssl req -new -x509 -days 3650 -key ca-key.pem -out ca-cert.pem \
  -subj "/C=US/O=MinervaDB/CN=MinervaDB CA"

# Generate server certificate
openssl genrsa -out server-key.pem 4096
openssl req -new -key server-key.pem -out server-csr.pem \
  -subj "/C=US/O=MinervaDB/CN=clickhouse.company.com"
openssl x509 -req -days 365 -in server-csr.pem \
  -CA ca-cert.pem -CAkey ca-key.pem -CAcreateserial \
  -out server-cert.pem

# Copy certs
cp ca-cert.pem server-cert.pem server-key.pem /etc/clickhouse-server/
chown clickhouse:clickhouse /etc/clickhouse-server/*.pem
chmod 600 /etc/clickhouse-server/server-key.pem
chmod 644 /etc/clickhouse-server/ca-cert.pem server-cert.pem
```

### ClickHouse TLS Configuration

```xml
<!-- config.d/02-networking.xml -->
<clickhouse>
  <!-- HTTPS interface (port 8443) -->
  <https_port>8443</https_port>
  <!-- TLS native protocol (port 9440) -->
  <tcp_port_secure>9440</tcp_port_secure>

  <openssl>
    <server>
      <certificateFile>/etc/clickhouse-server/server-cert.pem</certificateFile>
      <privateKeyFile>/etc/clickhouse-server/server-key.pem</privateKeyFile>
      <caConfig>/etc/clickhouse-server/ca-cert.pem</caConfig>
      <verificationMode>relaxed</verificationMode>  <!-- Change to "strict" for mTLS -->
      <loadDefaultCAFile>true</loadDefaultCAFile>
      <cacheSessions>true</cacheSessions>
      <disableProtocols>sslv2,sslv3,tlsv1,tlsv1_1</disableProtocols>
      <preferServerCiphers>true</preferServerCiphers>
      <requireTLSv1_2>true</requireTLSv1_2>
    </server>

    <client>
      <caConfig>/etc/clickhouse-server/ca-cert.pem</caConfig>
      <verificationMode>strict</verificationMode>
      <invalidCertificateHandler>
        <name>RejectCertificateHandler</name>
      </invalidCertificateHandler>
    </client>
  </openssl>
</clickhouse>
```

### Client Connection with TLS

```bash
# Connect with TLS
clickhouse-client --host ch.company.com \
  --port 9440 \
  --secure \
  --user analytics_user \
  --password 'StrongP@ssw0rd!' \
  --config-file /etc/clickhouse-client/config.xml

# Client config with TLS
cat > /etc/clickhouse-client/config.xml << 'EOF'
<config>
  <openssl>
    <client>
      <caConfig>/etc/ssl/certs/ca-cert.pem</caConfig>
      <verificationMode>strict</verificationMode>
    </client>
  </openssl>
</config>
EOF
```

---

## Network Security

### Firewall Rules (iptables/nftables)

```bash
# Allow ClickHouse ports only from trusted networks
# Native protocol
iptables -A INPUT -p tcp --dport 9000 -s 10.0.0.0/8 -j ACCEPT
iptables -A INPUT -p tcp --dport 9000 -j DROP

# HTTP interface
iptables -A INPUT -p tcp --dport 8123 -s 10.0.0.0/8 -j ACCEPT
iptables -A INPUT -p tcp --dport 8123 -j DROP

# TLS native
iptables -A INPUT -p tcp --dport 9440 -s 10.0.0.0/8 -j ACCEPT
iptables -A INPUT -p tcp --dport 9440 -j DROP

# HTTPS
iptables -A INPUT -p tcp --dport 8443 -s 10.0.0.0/8 -j ACCEPT
iptables -A INPUT -p tcp --dport 8443 -j DROP

# Interserver replication (only between CH nodes)
iptables -A INPUT -p tcp --dport 9009 -s 10.0.1.0/24 -j ACCEPT
iptables -A INPUT -p tcp --dport 9009 -j DROP

# Keeper
iptables -A INPUT -p tcp --dport 9181 -s 10.0.1.0/24 -j ACCEPT
iptables -A INPUT -p tcp --dport 9181 -j DROP
```

### Network Configuration

```xml
<!-- Restrict listen addresses -->
<clickhouse>
  <listen_host>0.0.0.0</listen_host>
  <!-- Or restrict to specific interface: -->
  <!-- <listen_host>10.0.1.10</listen_host> -->

  <!-- Disable plain text HTTP in production (use HTTPS only) -->
  <!-- Remove or comment out: <http_port>8123</http_port> -->
  <!-- Remove or comment out: <tcp_port>9000</tcp_port> -->
</clickhouse>
```

---

## Audit Logging

### Query Log for Audit Trail

```xml
<!-- Enable comprehensive query logging -->
<clickhouse>
  <query_log>
    <database>system</database>
    <table>query_log</table>
    <partition_by>toYYYYMM(event_date)</partition_by>
    <flush_interval_milliseconds>1000</flush_interval_milliseconds>
  </query_log>
</clickhouse>
```

### Audit Queries

```sql
-- All DDL operations (schema changes)
SELECT
    event_time,
    user,
    query_kind,
    databases,
    tables,
    left(query, 500) AS query
FROM system.query_log
WHERE query_kind IN ('Create', 'Drop', 'Alter', 'Rename')
  AND type = 'QueryFinish'
  AND event_time >= now() - INTERVAL 7 DAY
ORDER BY event_time DESC;

-- Failed authentication attempts
SELECT
    event_time,
    user,
    exception_code,
    exception,
    client_hostname
FROM system.query_log
WHERE type = 'ExceptionBeforeStart'
  AND exception_code = 516  -- ACCESS_DENIED
  AND event_time >= now() - INTERVAL 1 DAY
ORDER BY event_time DESC;

-- Data exfiltration detection (large result sets)
SELECT
    user,
    count() AS query_count,
    sum(result_rows) AS total_rows_returned,
    formatReadableSize(sum(result_bytes)) AS total_data_returned
FROM system.query_log
WHERE type = 'QueryFinish'
  AND result_rows > 1000000
  AND event_time >= now() - INTERVAL 1 DAY
GROUP BY user
ORDER BY total_data_returned DESC;

-- Queries accessing sensitive tables
SELECT
    event_time,
    user,
    left(query, 200) AS query
FROM system.query_log
WHERE hasAny(tables, ['users', 'payments', 'pii_data'])
  AND type = 'QueryFinish'
  AND event_time >= now() - INTERVAL 1 DAY
ORDER BY event_time DESC;
```

### External SIEM Integration

```yaml
# vector.toml — forward audit events to SIEM
[sources.clickhouse_audit]
type = "clickhouse"
endpoint = "http://localhost:8123"
query = """
  SELECT event_time, user, query_kind, query, exception, client_hostname
  FROM system.query_log
  WHERE event_time > now() - INTERVAL 1 MINUTE
  AND (query_kind IN ('Create','Drop','Alter') OR type = 'ExceptionBeforeStart')
  FORMAT JSONEachRow
"""
poll_interval_secs = 60

[sinks.siem]
type = "elasticsearch"
inputs = ["clickhouse_audit"]
endpoint = "https://siem.company.com:9200"
index = "clickhouse-audit-%Y.%m.%d"
```

---

## Secrets Management

### Using HashiCorp Vault

```bash
# Store ClickHouse passwords in Vault
vault kv put secret/clickhouse/users \
  analytics_password="StrongP@ssw0rd!" \
  kafka_password="kafka_secret"

# Retrieve and inject into config at startup
ANALYTICS_PASS=$(vault kv get -field=analytics_password secret/clickhouse/users)
export CLICKHOUSE_ANALYTICS_PASSWORD=$ANALYTICS_PASS
```

### Environment Variable Substitution

```xml
<!-- config.d/substitutions.xml -->
<clickhouse>
  <include_from>/etc/clickhouse-server/config-substitutions.xml</include_from>
</clickhouse>
```

```bash
# Generate substitutions file at runtime (from Vault or environment)
cat > /etc/clickhouse-server/config-substitutions.xml << EOF
<substitutions>
  <analytics_password>${ANALYTICS_PASSWORD}</analytics_password>
  <kafka_password>${KAFKA_PASSWORD}</kafka_password>
</substitutions>
EOF
```

---

## Security Checklist

### Pre-Production Security Review

- [ ] Default user disabled or restricted to localhost only
- [ ] All users have strong passwords (min 16 chars, mixed case, numbers, symbols)
- [ ] User access restricted by IP (`HOST IP` clause)
- [ ] TLS/HTTPS enabled on all ports; plain HTTP disabled
- [ ] TLS 1.0 and 1.1 disabled; TLS 1.2+ only
- [ ] RBAC implemented with least-privilege principle
- [ ] Row-level security policies applied for multi-tenant tables
- [ ] Sensitive columns excluded from low-privilege roles
- [ ] Firewall rules restricting ClickHouse ports to trusted networks
- [ ] Interserver authentication configured
- [ ] Query log TTL set and old logs cleaned
- [ ] Audit log shipped to external SIEM
- [ ] Backup credentials stored in secrets manager
- [ ] No credentials in config files checked into version control
- [ ] Regular security scanning of ClickHouse configuration
- [ ] Vulnerability scanning on ClickHouse binaries (match CVE database)

### Ongoing Security Operations

- [ ] Weekly review of `system.query_log` for anomalies
- [ ] Monthly access review (remove unused users/roles)
- [ ] Quarterly password rotation
- [ ] Regular update of ClickHouse to latest patch release
- [ ] Monitor for ClickHouse CVEs: https://clickhouse.com/docs/en/security-changelog

---

*Back to [MinervaDB Server Documentation](../README.md)*
