%global minervadb_version 24.12.1
%global minervadb_release 1
%global minervadb_src_dir  /opt/minervadb-server

Name:           minervadb-server
Version:        %{minervadb_version}
Release:        %{minervadb_release}%{?dist}
Summary:        MinervaDB Server for ClickHouse -- Enterprise-grade ClickHouse distribution
License:        Apache-2.0
URL:            https://github.com/MinervaDB/MinervaDB-Server
Source0:        https://github.com/MinervaDB/MinervaDB-Server/archive/refs/heads/main.tar.gz#/minervadb-server-%{minervadb_version}.tar.gz

# -----------------------------------------------------------------------
# This is a noarch (pure config + docs) package.
# The actual ClickHouse binaries are installed by clickhouse-server /
# clickhouse-client packages from packages.clickhouse.com.
# -----------------------------------------------------------------------
BuildArch:      noarch
BuildRequires:  coreutils
BuildRequires:  findutils

# Runtime dependencies
Requires:       clickhouse-server >= 24.1
Requires:       clickhouse-client >= 24.1
Requires:       clickhouse-keeper >= 24.1
Requires:       curl
Requires:       ca-certificates
Requires:       openssl

%description
MinervaDB Server for ClickHouse is an enterprise-grade distribution and
configuration overlay for ClickHouse -- the world's fastest open-source
real-time analytics database -- enhanced with curated extensions,
operational tooling, and comprehensive documentation covering:

  * Performance Engineering
  * Scalability (horizontal sharding + vertical tuning)
  * Observability & Monitoring (Prometheus, Grafana, OpenTelemetry)
  * Troubleshooting runbooks
  * Disaster Recovery (clickhouse-backup, S3/GCS/Azure)
  * High Availability (ClickHouse Keeper, HAProxy, rolling upgrades)

Installing this package:
  1. Drops production-hardened config.d / users.d XML overlays into
     /etc/clickhouse-server/
  2. Installs the full MinervaDB source tree under /opt/minervadb-server
  3. Installs monitoring assets (Prometheus rules + Grafana dashboards)
  4. Installs helper scripts for backup, diagnostics, and upgrades

After installation restart ClickHouse:
  systemctl restart clickhouse-server

# -----------------------------------------------------------------------
# Sub-package: docs
# -----------------------------------------------------------------------
%package docs
Summary:   Full operational documentation for MinervaDB Server for ClickHouse
BuildArch: noarch
Requires:  %{name} = %{version}-%{release}

%description docs
Comprehensive operational documentation for MinervaDB Server:
  PERFORMANCE.md, SCALABILITY.md, OBSERVABILITY.md, TROUBLESHOOTING.md,
  DR_HA.md, SECURITY.md, UPGRADE.md, CAPACITY_PLANNING.md,
  QUERY_OPTIMIZATION.md, KAFKA_INTEGRATION.md, KUBERNETES.md,
  BACKUP_RESTORE.md

Installed under /usr/share/doc/minervadb-server/

# -----------------------------------------------------------------------
# Sub-package: monitoring
# -----------------------------------------------------------------------
%package monitoring
Summary:   Prometheus alerting rules and Grafana dashboards for MinervaDB Server
BuildArch: noarch
Requires:  %{name} = %{version}-%{release}

%description monitoring
Prometheus alerting rules and pre-built Grafana dashboard JSON files for
monitoring MinervaDB Server / ClickHouse clusters.

Alert rules cover:
  ReplicationLagHigh, MergeBacklogHigh, DiskSpaceLow,
  QueryMemoryPressure, InsertQueueDepthHigh, ClickHouseDown,
  ZooKeeperSessionExpired

Grafana dashboards cover:
  Cluster Overview, MergeTree Internals, Replication Health,
  Query Performance, Insert Pipeline, Disk & Storage,
  Memory Pressure, Background Merges & Mutations

###########################################################################
%prep
###########################################################################
%autosetup -n MinervaDB-Server-main

###########################################################################
%build
###########################################################################
# Nothing to compile -- pure configuration and documentation package.
# Validate that critical source directories exist.
for d in docs; do
  test -d "$d" || (echo "ERROR: expected directory $d not found" && exit 1)
done

###########################################################################
%install
###########################################################################
# -- Core directories -----------------------------------------------------
install -d -m 0755 %{buildroot}/etc/clickhouse-server/config.d
install -d -m 0755 %{buildroot}/etc/clickhouse-server/users.d
install -d -m 0755 %{buildroot}%{minervadb_src_dir}
install -d -m 0755 %{buildroot}/usr/share/doc/minervadb-server
install -d -m 0755 %{buildroot}/usr/share/minervadb-server/monitoring/prometheus/alerts
install -d -m 0755 %{buildroot}/usr/share/minervadb-server/monitoring/grafana/dashboards

# -- Full source tree into /opt/minervadb-server --------------------------
cp -a . %{buildroot}%{minervadb_src_dir}/

# -- ClickHouse config overlays -------------------------------------------
if [ -d configs/production/config.d ]; then
  find configs/production/config.d -name "*.xml" -exec \
    install -m 0640 {} %{buildroot}/etc/clickhouse-server/config.d/ \;
fi
if [ -d configs/production/users.d ]; then
  find configs/production/users.d -name "*.xml" -exec \
    install -m 0640 {} %{buildroot}/etc/clickhouse-server/users.d/ \;
fi

# -- Monitoring assets ----------------------------------------------------
if [ -d monitoring/prometheus ]; then
  cp -a monitoring/prometheus/. \
    %{buildroot}/usr/share/minervadb-server/monitoring/prometheus/
fi
if [ -d monitoring/grafana/dashboards ]; then
  cp -a monitoring/grafana/dashboards/. \
    %{buildroot}/usr/share/minervadb-server/monitoring/grafana/dashboards/
fi

# -- Documentation --------------------------------------------------------
install -m 0644 README.md   %{buildroot}/usr/share/doc/minervadb-server/
install -m 0644 LICENSE     %{buildroot}/usr/share/doc/minervadb-server/
if [ -d docs ]; then
  cp -a docs/. %{buildroot}/usr/share/doc/minervadb-server/docs/
  install -d %{buildroot}/usr/share/doc/minervadb-server/docs
  cp docs/*.md %{buildroot}/usr/share/doc/minervadb-server/docs/ 2>/dev/null || true
fi

###########################################################################
%pre
###########################################################################
# Ensure the clickhouse group/user exist.
# (clickhouse-server RPM normally creates them, but guard for ordering.)
getent group  clickhouse >/dev/null || groupadd  -r clickhouse
getent passwd clickhouse >/dev/null || \
  useradd -r -g clickhouse -d /var/lib/clickhouse -s /sbin/nologin \
          -c "ClickHouse Server" clickhouse

###########################################################################
%post
###########################################################################
echo "================================================================="
echo " MinervaDB Server for ClickHouse %{minervadb_version} installed  "
echo "================================================================="
echo ""
echo "  Source tree    : %{minervadb_src_dir}"
echo "  Config overlays: /etc/clickhouse-server/config.d/"
echo "                   /etc/clickhouse-server/users.d/"
echo ""
echo "  Restart ClickHouse to activate the new configuration:"
echo "    systemctl restart clickhouse-server"
echo ""
echo "  Documentation  : /usr/share/doc/minervadb-server/"
echo "    or online    : https://github.com/MinervaDB/MinervaDB-Server"
echo "================================================================="

###########################################################################
%preun
###########################################################################
# We do not own the clickhouse-server service; nothing to stop here.

###########################################################################
%postun
###########################################################################
# On full removal (not upgrade), clean up /opt/minervadb-server.
if [ $1 -eq 0 ]; then
  rm -rf %{minervadb_src_dir}
fi

###########################################################################
%files
###########################################################################
%license LICENSE
%doc README.md
%dir %{minervadb_src_dir}
%{minervadb_src_dir}/configs
%{minervadb_src_dir}/scripts
%config(noreplace) /etc/clickhouse-server/config.d/
%config(noreplace) /etc/clickhouse-server/users.d/

%files docs
%doc README.md
%dir /usr/share/doc/minervadb-server
/usr/share/doc/minervadb-server/
%{minervadb_src_dir}/docs

%files monitoring
%dir /usr/share/minervadb-server
%dir /usr/share/minervadb-server/monitoring
/usr/share/minervadb-server/monitoring/

###########################################################################
%changelog
###########################################################################
* Thu Jun 18 2026 MinervaDB Engineering <engineering@minervadb.xyz> - 24.12.1-1
- Initial RPM packaging of MinervaDB Server for ClickHouse
- Noarch package: production config overlays, monitoring assets, full docs
- Sub-packages: minervadb-server-docs, minervadb-server-monitoring
