# Run in the NetBSD guest while provisioning (vm.sh). The base system has cc,
# gcc, make and atf; the suite also needs these, from pkgsrc binaries.
set -e
PATH=$PATH:/usr/sbin:/usr/pkg/sbin:/usr/pkg/bin; export PATH
arch=$(uname -p); rel=$(uname -r | cut -d. -f1).0
PKG_PATH="https://cdn.NetBSD.org/pub/pkgsrc/packages/NetBSD/$arch/$rel/All"; export PKG_PATH
pkg_add -v pkgconf cmake doxygen atf kyua clang lld
