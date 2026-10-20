# Run in the macOS tart guest (as admin, passwordless sudo): MacPorts packages
# the unit suite needs beyond bmake/gcc/llvm. Binary archives are used where
# MacPorts has them, so this is minutes rather than a compile.
set -e
export PATH=/opt/local/bin:/opt/local/sbin:$PATH
sudo port -N install pkgconfig cmake doxygen atf kyua unzip
