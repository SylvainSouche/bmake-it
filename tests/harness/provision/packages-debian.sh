# Run in the Debian guest while provisioning (vm.sh): the same packages as
# the linux-glibc Docker image (GLIBC_INSTALL in the Makefile).
set -e
export DEBIAN_FRONTEND=noninteractive
# cloud-init may still hold the apt lock right after first boot
cloud-init status --wait >/dev/null 2>&1 || true
apt-get update -qq
apt-get install -y -qq --no-install-recommends bmake clang lld gcc g++ file pkgconf curl ca-certificates cmake make bison flex doxygen kyua atf-sh libatf-dev unzip patch
