# Run in the FreeBSD guest while provisioning (vm.sh). The base system has
# clang, bmake (make) and file; the suite also needs these.
# Retried: a slow DNS relay (QEMU's, on a host with dead resolvers) can time
# out pkg's repository lookups ("No SRV record found", "Timeout was reached").
set -e
n=1
until env ASSUME_ALWAYS_YES=yes pkg install -y pkgconf gcc cmake-core doxygen atf; do
    [ "$n" -lt 3 ] || exit 1
    n=$((n + 1)); echo "pkg install failed; trying again ($n/3)"; sleep 10
done
