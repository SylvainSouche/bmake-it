# packages-freebsd.sh fetch|install <dir> -- run in the FreeBSD guest by vm.sh
# (guest-packages-from-cache-req). The base system has clang, bmake (make)
# and file; the suite also needs these.
#   fetch <dir>    download them and their dependencies (and pkg itself) into <dir>
#   install <dir>  install them from <dir>, with no network
# The fetch is retried: a slow DNS relay (QEMU's, on a host with dead
# resolvers) can time out pkg's repository lookups.
set -e
PKGS="pkgconf gcc cmake-core doxygen atf"
mode=${1:?fetch or install}; dir=${2:?directory}
export ASSUME_ALWAYS_YES=yes
case "$mode" in
    fetch)
        n=1
        until { pkg -N >/dev/null 2>&1 || pkg bootstrap -y; } && pkg update && pkg fetch -y -d -o "$dir" pkg $PKGS; do
            [ "$n" -lt 3 ] || exit 1
            n=$((n + 1)); echo "pkg fetch failed; trying again ($n/3)"; sleep 10
        done ;;
    install)
        # pkg itself first (the base system's /usr/sbin/pkg bootstraps from
        # the file), then each package: pkg add finds the dependencies in
        # the same directory
        # (newer repositories keep the files under All/Hashed/)
        f() { find "$dir" -name "$1-[0-9]*.pkg" | head -1; }
        pkg -N >/dev/null 2>&1 || /usr/sbin/pkg add "$(f pkg)"
        for p in $PKGS; do pkg add "$(f "$p")"; done ;;
esac
