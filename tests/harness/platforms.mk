# platforms.mk — single source of truth for the test matrix.
# Included by Makefile. Every platform ID uses underscores (not hyphens) so
# it can appear directly inside a make variable name, e.g. $(KIND_$(p)).
#
# Fields per platform ID <p>:
#   KIND_<p>      docker | vm | vm-host   (vm-host = macOS VM on this host)
#   ARCH_<p>      amd64 | arm64
#   TIER_<p>      1 | 2                   (2 = best-effort, lower priority)
#   TOOLCHAINS_<p> space-separated: llvm gcc
#   DOCKERFILE_<p> (docker only) path under provision/docker/
#   PLATFORM_<p>  (docker only) --platform value, empty = host arch
#   IMAGE_URL_<p> (vm only) source URL for the disk image
#   SSH_PORT_<p>  (vm only) forwarded host port for ssh

# freebsd_amd64 and netbsd_amd64 are FROZEN (2026-09-02): both stall
# deterministically at the identical boot-loader-to-kernel transition point
# under QEMU/TCG on this host -- 8 independent config variants (virtio vs
# IDE disk, bare virtio-rng-pci vs explicit rng-random backend, -M pc vs
# q35, smp=2 vs 1, -vga none/-nodefaults, RDRAND/RDSEED disabled) all fail
# identically. Not in $(PLATFORMS) until this is resolved -- see
# OBS-qemu-tcg-x86-64-boot-stall-on-host. Their entries are kept below
# (commented out of the active list only) since the fetch/provision recipes
# and confirmed image URLs are still valid and this may get revisited.
PLATFORMS = macos_arm64 linux_amd64_emu linux_amd64_vm linux_arm64 \
            linux_amd64_musl netbsd_arm64
# PLATFORMS += freebsd_amd64 netbsd_amd64   # frozen, see above

# --- macOS (VM, Virtualization.framework via tart) ---------------------
KIND_macos_arm64        = vm-host
ARCH_macos_arm64         = arm64
TIER_macos_arm64          = 1
TOOLCHAINS_macos_arm64     = llvm gcc

# --- Linux glibc amd64, Docker + qemu-user emulation --------------------
KIND_linux_amd64_emu    = docker
ARCH_linux_amd64_emu     = amd64
TIER_linux_amd64_emu      = 1
TOOLCHAINS_linux_amd64_emu = llvm gcc
DOCKERFILE_linux_amd64_emu = Dockerfile.linux-glibc
PLATFORM_linux_amd64_emu   = linux/amd64

# --- Linux glibc amd64, full QEMU VM (genuine kernel boot) --------------
KIND_linux_amd64_vm     = vm
ARCH_linux_amd64_vm      = amd64
TIER_linux_amd64_vm       = 1
TOOLCHAINS_linux_amd64_vm  = llvm gcc
IMAGE_URL_linux_amd64_vm   = https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2
SSH_PORT_linux_amd64_vm    = 2223

# --- Linux glibc arm64, Docker native arch -------------------------------
KIND_linux_arm64        = docker
ARCH_linux_arm64          = arm64
TIER_linux_arm64           = 1
TOOLCHAINS_linux_arm64      = llvm gcc
DOCKERFILE_linux_arm64      = Dockerfile.linux-glibc
PLATFORM_linux_arm64        =

# --- Linux musl amd64, Docker + qemu-user emulation (2nd tier) ----------
KIND_linux_amd64_musl   = docker
ARCH_linux_amd64_musl    = amd64
TIER_linux_amd64_musl     = 2
TOOLCHAINS_linux_amd64_musl = llvm gcc
DOCKERFILE_linux_amd64_musl = Dockerfile.linux-musl
PLATFORM_linux_amd64_musl   = linux/amd64

# --- FreeBSD amd64, QEMU VM (TCG) ----------------------------------------
KIND_freebsd_amd64      = vm
ARCH_freebsd_amd64        = amd64
TIER_freebsd_amd64         = 1
TOOLCHAINS_freebsd_amd64    = llvm gcc
IMAGE_URL_freebsd_amd64     = https://download.freebsd.org/releases/VM-IMAGES/14.3-RELEASE/amd64/Latest/FreeBSD-14.3-RELEASE-amd64.qcow2.xz
SSH_PORT_freebsd_amd64      = 2224

# --- NetBSD amd64, QEMU VM (TCG) -----------------------------------------
KIND_netbsd_amd64       = vm
ARCH_netbsd_amd64         = amd64
TIER_netbsd_amd64          = 1
TOOLCHAINS_netbsd_amd64     = llvm gcc
# The "-live" variant is the ready-to-boot image (not the installer ISO) --
# NetBSD publishes ready-to-dd images for multiple ports, not just evbarm.
IMAGE_URL_netbsd_amd64      = https://cdn.netbsd.org/pub/NetBSD/images/10.1/NetBSD-10.1-amd64-live.img.gz
SSH_PORT_netbsd_amd64       = 2225

# --- NetBSD arm64, QEMU VM (hvf-accelerated) — 2nd tier -------------------
KIND_netbsd_arm64       = vm
ARCH_netbsd_arm64         = arm64
TIER_netbsd_arm64          = 2
TOOLCHAINS_netbsd_arm64     = llvm gcc
IMAGE_URL_netbsd_arm64      = https://cdn.netbsd.org/pub/NetBSD/NetBSD-10.1/evbarm-aarch64/binary/gzimg/arm64.img.gz
SSH_PORT_netbsd_arm64       = 2222

# --- Pending, documented only (see plan) ---------------------------------
# windows: msvc + llvm + gcc, Microsoft ABI primary, cygwin/mingw 2nd tier.
# Blocked on a new mk.toolchain.msvc.mk in the product itself -- not a
# test-infrastructure gap. Not in $(PLATFORMS); tracked here so the design
# accounts for it.
