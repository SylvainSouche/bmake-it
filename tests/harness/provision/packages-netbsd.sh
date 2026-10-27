# Run in the NetBSD guest while provisioning (vm.sh). The base system has cc,
# gcc, make and atf; the suite also needs these, from pkgsrc binaries.
set -e
PATH=$PATH:/usr/sbin:/usr/pkg/sbin:/usr/pkg/bin; export PATH
arch=$(uname -p); rel=$(uname -r | cut -d. -f1).0
PKG_PATH="https://cdn.NetBSD.org/pub/pkgsrc/packages/NetBSD/$arch/$rel/All"; export PKG_PATH

# An interrupted pkg_add (a dropped download or ssh session) can leave a
# package recorded as installed with files missing ("missing required
# library" for every package that needs it): remove those, so they are
# installed again.
repair() {
    for p in $(pkg_info -e '*' 2>/dev/null || pkg_info | awk '{print $1}'); do
        pkg_admin check "$p" >/dev/null 2>&1 || { echo "removing incomplete $p"; pkg_delete -f "$p" || true; }
    done
}

repair
n=1
until pkg_add -v pkgconf cmake doxygen atf kyua clang lld; do
    [ "$n" -lt 3 ] || exit 1
    n=$((n + 1)); echo "pkg_add failed; repairing and trying again ($n/3)"; sleep 5
    repair
done
