# MinervaDB Server for ClickHouse -- Packaging

This directory contains everything needed to build distributable packages of
**MinervaDB Server for ClickHouse** for the two major Linux families:

| Platform | Package format | Target distributions |
|----------|---------------|----------------------|
| RHEL / CentOS / Rocky Linux / AlmaLinux | `.rpm` | RHEL 8+, CentOS Stream 8+, Rocky Linux 8/9, AlmaLinux 8/9 |
| Ubuntu / Debian | `.deb` | Ubuntu 20.04 LTS, 22.04 LTS, 24.04 LTS; Debian 11/12 |

---

## Directory layout

```
packaging/
├── README.md                     # This file
├── build-packages.sh             # Master build script (auto-detects OS family)
├── rpm/
│   └── minervadb-server.spec     # RPM spec file (rpmbuild)
└── deb/
    └── DEBIAN/
        ├── control               # Package metadata
        ├── postinst              # Post-install hook
        ├── prerm                 # Pre-remove hook
        └── postrm                # Post-remove hook
```

---

## What gets installed

| Path | Contents |
|------|----------|
| `/opt/minervadb-server/` | Full MinervaDB source tree |
| `/etc/clickhouse-server/config.d/*.xml` | Production-hardened ClickHouse config overlays |
| `/etc/clickhouse-server/users.d/*.xml` | Production user profile overlays |
| `/usr/share/doc/minervadb-server/` | README, LICENSE, and all docs |
| `/usr/share/minervadb-server/monitoring/` | Prometheus rules + Grafana dashboards |

> Config files under `/etc/clickhouse-server/` are marked **conffiles** so
> your local edits are preserved across upgrades.

---

## Prerequisites

### RPM (RHEL / CentOS / Rocky / AlmaLinux)

```bash
sudo dnf install -y rpm-build rpmdevtools git
```

### DEB (Ubuntu / Debian)

```bash
sudo apt-get install -y dpkg-dev fakeroot git
```

---

## Building packages

```bash
git clone https://github.com/MinervaDB/MinervaDB-Server.git
cd MinervaDB-Server
chmod +x packaging/build-packages.sh

# Auto-detect OS and build:
./packaging/build-packages.sh

# Or build explicitly:
./packaging/build-packages.sh rpm   # .rpm only
./packaging/build-packages.sh deb   # .deb only
./packaging/build-packages.sh all   # both .rpm and .deb
```

Override version:

```bash
MINERVADB_VERSION=24.12.1 MINERVADB_RELEASE=2 ./packaging/build-packages.sh all
```

Output is written to `dist/`.

---

## Installing

### RHEL / CentOS / Rocky / AlmaLinux

```bash
# 1. Add ClickHouse upstream repo
sudo dnf install -y yum-utils
sudo yum-config-manager --add-repo https://packages.clickhouse.com/rpm/clickhouse.repo
sudo dnf install -y clickhouse-server clickhouse-client clickhouse-keeper

# 2. Install MinervaDB Server
sudo rpm -ivh dist/minervadb-server-*.noarch.rpm

# 3. Enable and restart ClickHouse
sudo systemctl enable --now clickhouse-server
sudo systemctl restart clickhouse-server
```

### Ubuntu / Debian

```bash
# 1. Add ClickHouse upstream repo
sudo apt-get install -y apt-transport-https ca-certificates curl gnupg
curl -fsSL https://packages.clickhouse.com/rpm/lts/repodata/repomd.xml.key \
  | sudo gpg --dearmor -o /usr/share/keyrings/clickhouse-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/clickhouse-archive-keyring.gpg] \
  https://packages.clickhouse.com/deb stable main" \
  | sudo tee /etc/apt/sources.list.d/clickhouse.list
sudo apt-get update && sudo apt-get install -y clickhouse-server clickhouse-client

# 2. Install MinervaDB Server
sudo dpkg -i dist/minervadb-server_*_all.deb

# 3. Enable and restart ClickHouse
sudo systemctl enable --now clickhouse-server
sudo systemctl restart clickhouse-server
```

---

## Automated builds (GitHub Actions)

The workflow `.github/workflows/build-packages.yml` builds `.rpm` and `.deb`
automatically on every version tag and attaches them to the GitHub Release.

```bash
git tag v24.12.1
git push origin v24.12.1
```

---

## Sub-packages (RPM only)

| Package | Contents |
|---------|----------|
| `minervadb-server` | Core config overlays + source tree |
| `minervadb-server-docs` | Full documentation |
| `minervadb-server-monitoring` | Prometheus rules + Grafana dashboards |

---

## Uninstalling

```bash
# RPM
sudo rpm -e minervadb-server

# DEB (remove but keep config files)
sudo dpkg -r minervadb-server

# DEB (purge -- removes /opt/minervadb-server too)
sudo dpkg --purge minervadb-server
```

---

## Support

- GitHub Issues: https://github.com/MinervaDB/MinervaDB-Server/issues
- Website: https://minervadb.xyz
- Email: engineering@minervadb.xyz
