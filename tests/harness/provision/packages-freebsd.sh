# Run in the FreeBSD guest while provisioning (vm.sh). The base system has
# clang, bmake (make) and file; the suite also needs these.
set -e
env ASSUME_ALWAYS_YES=yes pkg install -y pkgconf gcc cmake-core doxygen atf
