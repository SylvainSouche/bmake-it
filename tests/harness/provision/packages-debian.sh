# packages-debian.sh fetch|install <dir> -- run in the Debian guest by vm.sh
# (guest-packages-from-cache-req): the same packages as the linux-glibc
# Docker image (GLIBC_INSTALL in the Makefile).
#   fetch <dir>    download them, with every dependency the image lacks, into <dir>
#   install <dir>  install them from <dir>, with no network
set -e
export DEBIAN_FRONTEND=noninteractive
PKGS="bmake clang lld gcc g++ file pkgconf curl ca-certificates cmake make bison flex doxygen kyua atf-sh libatf-dev unzip patch"
mode=${1:?fetch or install}; dir=${2:?directory}
# cloud-init may still hold the apt lock right after first boot
cloud-init status --wait >/dev/null 2>&1 || true
case "$mode" in
    fetch)
        apt-get update -qq
        apt-get clean
        apt-get install -y -qq --no-install-recommends --download-only $PKGS
        mkdir -p "$dir"; cp /var/cache/apt/archives/*.deb "$dir"/ ;;
    install)
        apt-get install -y -qq --no-install-recommends "$dir"/*.deb
        # A test guest keeps the clock it booted with (the host's): NTP
        # stepping it back mid-suite made mtime-based rebuild checks fail
        # (case 54; a host clock 6 minutes fast, 2026-10-27)
        timedatectl set-ntp false 2>/dev/null || systemctl disable --now systemd-timesyncd 2>/dev/null || true ;;
esac
