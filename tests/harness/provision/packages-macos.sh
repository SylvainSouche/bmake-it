# Run in the macOS tart guest (as admin, passwordless sudo): MacPorts packages
# the unit suite needs beyond bmake/gcc/llvm. Binary archives are used where
# MacPorts has them, so this is minutes rather than a compile.
set -e
export PATH=/opt/local/bin:/opt/local/sbin:$PATH
# Tools the unit suite needs: bmake gcc llvm (already in the guest), pkgconfig atf kyua
# cmake doxygen unzip curl. Libraries real projects import with IMPORT=pkg: (OpenRider /
# garminviewer): glfw tiff. A cross build cannot get any of these from a sysroot
# (cross-sysroot-os-only-obs): on macOS they are native, so the guest is where they must be.
sudo port -N install bmake pkgconfig atf kyua cmake doxygen unzip curl glfw tiff
