#!/usr/bin/env bash
# =============================================================================
# build-packages.sh
# MinervaDB Server for ClickHouse — package builder
#
# Builds distributable packages for:
#   RHEL / CentOS / Rocky / AlmaLinux  ->  .rpm  (via rpmbuild)
#   Ubuntu / Debian                    ->  .deb  (via dpkg-deb)
#
# Usage:
#   ./packaging/build-packages.sh [rpm|deb|all]
#
# Prerequisites:
#   rpm  : rpm-build, rpmdevtools   (dnf install rpm-build rpmdevtools)
#   deb  : dpkg-dev, fakeroot       (apt-get install dpkg-dev fakeroot)
#
# The script auto-detects the OS family when no argument is supplied.
# =============================================================================
set -euo pipefail

###############################################################################
# Configuration
###############################################################################
MINERVADB_VERSION="${MINERVADB_VERSION:-24.12.1}"
MINERVADB_RELEASE="${MINERVADB_RELEASE:-1}"
PACKAGE_NAME="minervadb-server"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGING_DIR="${REPO_ROOT}/packaging"
OUTPUT_DIR="${REPO_ROOT}/dist"

###############################################################################
# Helpers
###############################################################################
info()  { echo "[INFO]  $*"; }
warn()  { echo "[WARN]  $*" >&2; }
error() { echo "[ERROR] $*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || \
    error "Required command not found: $1. Install it and retry."
}

detect_os_family() {
  if [ -f /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    case "${ID_LIKE:-${ID}}" in
      *rhel*|*fedora*|*centos*|*rocky*|*alma*) echo "rpm" ;;
      *debian*|*ubuntu*)                        echo "deb" ;;
      *) echo "unknown" ;;
    esac
  else
    echo "unknown"
  fi
}

###############################################################################
# RPM build (.rpm for RHEL/CentOS/Rocky/AlmaLinux)
###############################################################################
build_rpm() {
  info "==================================================================="
  info " Building RPM package for RHEL / CentOS / Rocky / AlmaLinux"
  info "==================================================================="

  require_cmd rpmbuild
  require_cmd spectool 2>/dev/null || require_cmd curl

  local rpm_topdir
  rpm_topdir="${HOME}/rpmbuild"
  rpmdev-setuptree 2>/dev/null || mkdir -p \
    "${rpm_topdir}"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

  # ── Copy spec file ────────────────────────────────────────────────────
  cp "${PACKAGING_DIR}/rpm/minervadb-server.spec" "${rpm_topdir}/SPECS/"

  # ── Create source tarball from the repo ────────────────────────────────
  info "Creating source tarball ..."
  local tarball_name
  tarball_name="${PACKAGE_NAME}-${MINERVADB_VERSION}"
  local tarball_path
  tarball_path="${rpm_topdir}/SOURCES/${tarball_name}.tar.gz"

  git -C "${REPO_ROOT}" archive \
    --format=tar.gz \
    --prefix="MinervaDB-Server-main/" \
    HEAD \
    -o "${tarball_path}"

  # ── Build the RPM ─────────────────────────────────────────────────────
  info "Running rpmbuild ..."
  rpmbuild -ba \
    --define "_topdir ${rpm_topdir}" \
    --define "minervadb_version ${MINERVADB_VERSION}" \
    --define "minervadb_release ${MINERVADB_RELEASE}" \
    "${rpm_topdir}/SPECS/minervadb-server.spec"

  # ── Collect output ─────────────────────────────────────────────────────
  mkdir -p "${OUTPUT_DIR}"
  find "${rpm_topdir}/RPMS" -name "*.rpm" -exec cp {} "${OUTPUT_DIR}/" \;
  find "${rpm_topdir}/SRPMS" -name "*.src.rpm" -exec cp {} "${OUTPUT_DIR}/" \;

  info "RPM packages written to: ${OUTPUT_DIR}"
  ls -lh "${OUTPUT_DIR}"/*.rpm 2>/dev/null || true
}

###############################################################################
# DEB build (.deb for Ubuntu / Debian)
###############################################################################
build_deb() {
  info "==================================================================="
  info " Building DEB package for Ubuntu / Debian"
  info "==================================================================="

  require_cmd dpkg-deb
  require_cmd fakeroot

  local deb_staging
  deb_staging="$(mktemp -d)"
  trap 'rm -rf "${deb_staging}"' EXIT

  local pkg_dir
  pkg_dir="${deb_staging}/${PACKAGE_NAME}_${MINERVADB_VERSION}-${MINERVADB_RELEASE}_all"

  # ── Directory skeleton ─────────────────────────────────────────────────
  install -d -m 0755 "${pkg_dir}/DEBIAN"
  install -d -m 0755 "${pkg_dir}/opt/minervadb-server"
  install -d -m 0755 "${pkg_dir}/etc/clickhouse-server/config.d"
  install -d -m 0755 "${pkg_dir}/etc/clickhouse-server/users.d"
  install -d -m 0755 "${pkg_dir}/usr/share/doc/minervadb-server"
  install -d -m 0755 "${pkg_dir}/usr/share/minervadb-server/monitoring/prometheus"
  install -d -m 0755 "${pkg_dir}/usr/share/minervadb-server/monitoring/grafana/dashboards"

  # ── Copy DEBIAN control files ─────────────────────────────────────────
  install -m 0644 "${PACKAGING_DIR}/deb/DEBIAN/control"  "${pkg_dir}/DEBIAN/"
  install -m 0755 "${PACKAGING_DIR}/deb/DEBIAN/postinst" "${pkg_dir}/DEBIAN/"
  install -m 0755 "${PACKAGING_DIR}/deb/DEBIAN/prerm"    "${pkg_dir}/DEBIAN/"
  install -m 0755 "${PACKAGING_DIR}/deb/DEBIAN/postrm"   "${pkg_dir}/DEBIAN/"

  # ── Update version in control file ────────────────────────────────────
  sed -i "s/^Version:.*/Version: ${MINERVADB_VERSION}-${MINERVADB_RELEASE}/" \
    "${pkg_dir}/DEBIAN/control"

  # ── Copy source tree into /opt/minervadb-server ───────────────────────
  cp -a "${REPO_ROOT}/." "${pkg_dir}/opt/minervadb-server/"
  # Remove the packaging dir itself to avoid recursion
  rm -rf "${pkg_dir}/opt/minervadb-server/packaging"
  rm -rf "${pkg_dir}/opt/minervadb-server/dist"

  # ── ClickHouse config overlays ────────────────────────────────────────
  if [ -d "${REPO_ROOT}/configs/production/config.d" ]; then
    find "${REPO_ROOT}/configs/production/config.d" -name "*.xml" \
      -exec install -m 0640 {} "${pkg_dir}/etc/clickhouse-server/config.d/" \;
  fi
  if [ -d "${REPO_ROOT}/configs/production/users.d" ]; then
    find "${REPO_ROOT}/configs/production/users.d" -name "*.xml" \
      -exec install -m 0640 {} "${pkg_dir}/etc/clickhouse-server/users.d/" \;
  fi

  # ── Monitoring assets ─────────────────────────────────────────────────
  if [ -d "${REPO_ROOT}/monitoring/prometheus" ]; then
    cp -a "${REPO_ROOT}/monitoring/prometheus/." \
      "${pkg_dir}/usr/share/minervadb-server/monitoring/prometheus/"
  fi
  if [ -d "${REPO_ROOT}/monitoring/grafana/dashboards" ]; then
    cp -a "${REPO_ROOT}/monitoring/grafana/dashboards/." \
      "${pkg_dir}/usr/share/minervadb-server/monitoring/grafana/dashboards/"
  fi

  # ── Documentation ────────────────────────────────────────────────────
  install -m 0644 "${REPO_ROOT}/README.md" "${pkg_dir}/usr/share/doc/minervadb-server/"
  install -m 0644 "${REPO_ROOT}/LICENSE"   "${pkg_dir}/usr/share/doc/minervadb-server/"
  if [ -d "${REPO_ROOT}/docs" ]; then
    install -d "${pkg_dir}/usr/share/doc/minervadb-server/docs"
    find "${REPO_ROOT}/docs" -name "*.md" \
      -exec install -m 0644 {} "${pkg_dir}/usr/share/doc/minervadb-server/docs/" \;
  fi

  # ── conffiles manifest (prevents dpkg overwriting user edits) ─────────
  find "${pkg_dir}/etc" -type f | \
    sed "s|${pkg_dir}||" > "${pkg_dir}/DEBIAN/conffiles"

  # ── Compute installed size ────────────────────────────────────────────
  local installed_size
  installed_size=$(du -sk "${pkg_dir}" | cut -f1)
  sed -i "s/^Installed-Size:.*/Installed-Size: ${installed_size}/" \
    "${pkg_dir}/DEBIAN/control"

  # ── Build the .deb ────────────────────────────────────────────────────
  mkdir -p "${OUTPUT_DIR}"
  local deb_file
  deb_file="${OUTPUT_DIR}/${PACKAGE_NAME}_${MINERVADB_VERSION}-${MINERVADB_RELEASE}_all.deb"

  info "Running fakeroot dpkg-deb ..."
  fakeroot dpkg-deb --build "${pkg_dir}" "${deb_file}"

  info "DEB package written to: ${deb_file}"
  ls -lh "${deb_file}"
}

###############################################################################
# Main
###############################################################################
main() {
  local target="${1:-auto}"

  if [ "${target}" = "auto" ]; then
    target="$(detect_os_family)"
    if [ "${target}" = "unknown" ]; then
      error "Cannot auto-detect OS family. Specify rpm or deb explicitly."
    fi
    info "Auto-detected OS family: ${target}"
  fi

  case "${target}" in
    rpm) build_rpm ;;
    deb) build_deb ;;
    all)
      build_rpm
      build_deb
      ;;
    *)
      error "Unknown target: ${target}. Use: rpm | deb | all"
      ;;
  esac

  info "==================================================================="
  info " Done!  Packages are in: ${OUTPUT_DIR}"
  info "==================================================================="
}

main "$@"
