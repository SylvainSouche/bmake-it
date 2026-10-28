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
            linux_amd64_musl netbsd_arm64 freebsd_arm64
# PLATFORMS += freebsd_amd64 netbsd_amd64   # frozen, see above

# --- macOS (VM, Virtualization.framework via tart) ---------------------
KIND_macos_arm64        = vm-host
TARTVM_macos_arm64       = rade-bmake-macos
ARCH_macos_arm64         = arm64
TIER_macos_arm64          = 1
TOOLCHAINS_macos_arm64     = llvm gcc

# IMAGE_<id> (docker platforms): the tag run-native-docker.sh and matrix.sh use.
# BMAKE_<id> (vm platforms): the make that is bmake on that system.

# --- Linux glibc amd64, Docker + qemu-user emulation --------------------
KIND_linux_amd64_emu    = docker
ARCH_linux_amd64_emu     = amd64
TIER_linux_amd64_emu      = 1
TOOLCHAINS_linux_amd64_emu = llvm gcc
DOCKERFILE_linux_amd64_emu = Dockerfile.linux-glibc
PLATFORM_linux_amd64_emu   = linux/amd64
IMAGE_linux_amd64_emu = bmk/linux-glibc:amd64

# --- Linux glibc amd64, full QEMU VM (genuine kernel boot) --------------
KIND_linux_amd64_vm     = vm
ARCH_linux_amd64_vm      = amd64
TIER_linux_amd64_vm       = 1
TOOLCHAINS_linux_amd64_vm  = llvm gcc
IMAGE_URL_linux_amd64_vm   = https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2
SSH_PORT_linux_amd64_vm    = 2223
# No serial-console login on a cloud image: cloud-init takes the harness key
# from user-data vm.sh serves over HTTP (PROVISION cloud-init).
IMAGE_FILE_linux_amd64_vm  = debian-13-genericcloud-amd64.qcow2
IMAGE_COMP_linux_amd64_vm  = none
IMAGE_FMT_linux_amd64_vm   = qcow2
BOOT_linux_amd64_vm        = uefi-amd64
PKGCACHE_linux_amd64_vm    = debian-13-amd64
MEM_linux_amd64_vm         = 3072
PROVISION_linux_amd64_vm   = cloud-init
LAYER_SIZE_linux_amd64_vm  = 12G
PKGSCRIPT_linux_amd64_vm   = debian
BMAKE_linux_amd64_vm       = bmake

# --- Linux glibc arm64, Docker native arch -------------------------------
KIND_linux_arm64        = docker
ARCH_linux_arm64          = arm64
TIER_linux_arm64           = 1
TOOLCHAINS_linux_arm64      = llvm gcc
DOCKERFILE_linux_arm64      = Dockerfile.linux-glibc
PLATFORM_linux_arm64        =
IMAGE_linux_arm64 = bmk/linux-glibc:arm64

# --- Linux musl amd64, Docker + qemu-user emulation (2nd tier) ----------
KIND_linux_amd64_musl   = docker
ARCH_linux_amd64_musl    = amd64
TIER_linux_amd64_musl     = 2
TOOLCHAINS_linux_amd64_musl = llvm gcc
DOCKERFILE_linux_amd64_musl = Dockerfile.linux-musl
PLATFORM_linux_amd64_musl   = linux/amd64
IMAGE_linux_amd64_musl = bmk/linux-musl:amd64

# --- FreeBSD amd64, QEMU VM (TCG) ----------------------------------------
# Frozen set per harness-target-matrix-reconciled-req is {14.4, 15.0, 15.1};
# single-pinned to the latest (15.1) for now -- tracking all three
# simultaneously needs harness-cache-management-cli-req/version-freshness-
# caching-policy-req, not yet implemented. Filename convention changed
# since 14.3 (now requires an explicit -ufs/-zfs suffix) -- confirmed via
# the real 15.1 directory listing, not guessed.
KIND_freebsd_amd64      = vm
ARCH_freebsd_amd64        = amd64
TIER_freebsd_amd64         = 1
TOOLCHAINS_freebsd_amd64    = llvm gcc
IMAGE_URL_freebsd_amd64     = https://download.freebsd.org/releases/VM-IMAGES/15.1-RELEASE/amd64/Latest/FreeBSD-15.1-RELEASE-amd64-ufs.qcow2.xz
SSH_PORT_freebsd_amd64      = 2224

# --- NetBSD amd64, QEMU VM (TCG) -----------------------------------------
# Frozen set is {10.1, 11.0}; single-pinned to 11.0 for the same reason as
# FreeBSD above. URL confirmed via the real 11.0 directory listing.
KIND_netbsd_amd64       = vm
ARCH_netbsd_amd64         = amd64
TIER_netbsd_amd64          = 1
TOOLCHAINS_netbsd_amd64     = llvm gcc
# The "-live" variant is the ready-to-boot image (not the installer ISO) --
# NetBSD publishes ready-to-dd images for multiple ports, not just evbarm.
IMAGE_URL_netbsd_amd64      = https://cdn.netbsd.org/pub/NetBSD/images/11.0/NetBSD-11.0-amd64-live.img.gz
SSH_PORT_netbsd_amd64       = 2225

# --- NetBSD arm64, QEMU VM (hvf-accelerated) — 2nd tier -------------------
KIND_netbsd_arm64       = vm
ARCH_netbsd_arm64         = arm64
TIER_netbsd_arm64          = 2
TOOLCHAINS_netbsd_arm64     = llvm gcc
# 10.2, not the 11.0 the frozen set names: NetBSD 11.0 panics on Apple silicon
# under hvf ("unknown CPU ... Illegal Instruction" in cpu_rescan, 2026-10-20);
# 10.2 boots. Revisit when 11.x runs there (OBS netbsd-11-arm64-hvf-panic).
IMAGE_URL_netbsd_arm64      = https://cdn.netbsd.org/pub/NetBSD/NetBSD-10.2/evbarm-aarch64/binary/gzimg/arm64.img.gz
SSH_PORT_netbsd_arm64       = 2222

# --- FreeBSD arm64, QEMU VM (hvf-accelerated on an Apple-silicon host) ----
# The practical FreeBSD runtime on this host: unlike freebsd_amd64 (TCG,
# frozen) it boots in well under a minute (harness-arm64-bsd-native-dec).
KIND_freebsd_arm64      = vm
ARCH_freebsd_arm64        = arm64
TIER_freebsd_arm64         = 1
TOOLCHAINS_freebsd_arm64    = llvm gcc
IMAGE_URL_freebsd_arm64     = https://download.freebsd.org/releases/VM-IMAGES/15.1-RELEASE/aarch64/Latest/FreeBSD-15.1-RELEASE-arm64-aarch64-ufs.qcow2.xz
SSH_PORT_freebsd_arm64      = 2226

# --- How a vm platform is fetched, prepared and booted (vm.sh) --------------
#   IMAGE_FILE  name under $(BMK_CACHE)/images       IMAGE_COMP xz | gz | none
#   IMAGE_FMT   disk format after decompression      BOOT uefi-arm64 | bios-amd64
#   MEM         guest MiB (default 2048)             CONSOLE provision/console-<name>.txt
#   LAYER_SIZE  virtual size of the provisioned layer when the base is too small
#   PKGSCRIPT   provision/packages-<name>.sh, run in the guest while provisioning:
#               installs what the suite needs
#   BLOCKED     if set, the reason vm.sh refuses to boot it
#   NEEDS_ACCEL if set, the guest needs hardware acceleration (hvf, kvm,
#               whpx: a host of its own architecture); vm.sh refuses to boot
#               it under TCG, giving this reason
#   NIC         the QEMU network device (default virtio-net-pci)
#   PKGCACHE    <os>-<version>-<arch>: the guest's packages are kept in
#               $(BMK_CACHE)/packages/<this>/ and installed from there
#               (guest-packages-from-cache-req; filled on first provisioning)
#   PROVISION   console (default: CONSOLE script over the serial console) |
#               cloud-init (a cloud image: user-data served over HTTP)
IMAGE_FILE_freebsd_arm64 = FreeBSD-15.1-RELEASE-arm64-aarch64-ufs.qcow2.xz
IMAGE_COMP_freebsd_arm64 = xz
IMAGE_FMT_freebsd_arm64  = qcow2
BOOT_freebsd_arm64       = uefi-arm64
MEM_freebsd_arm64        = 2560
CONSOLE_freebsd_arm64    = freebsd
PKGSCRIPT_freebsd_arm64   = freebsd
PKGCACHE_freebsd_arm64    = freebsd-15.1-arm64

IMAGE_FILE_netbsd_arm64  = NetBSD-10.2-arm64.img.gz
IMAGE_COMP_netbsd_arm64  = gz
IMAGE_FMT_netbsd_arm64   = raw
BOOT_netbsd_arm64        = uefi-arm64
MEM_netbsd_arm64         = 2560
CONSOLE_netbsd_arm64     = netbsd
LAYER_SIZE_netbsd_arm64  = 12G
PKGSCRIPT_netbsd_arm64   = netbsd
PKGCACHE_netbsd_arm64    = netbsd-10.2-arm64

IMAGE_FILE_freebsd_amd64 = FreeBSD-15.1-RELEASE-amd64-ufs.qcow2.xz
IMAGE_COMP_freebsd_amd64 = xz
IMAGE_FMT_freebsd_amd64  = qcow2
# UEFI (amd64-guests-uefi-boot-req): the console is serial from the firmware
# on, as on arm64. (With bios-amd64 the loader's console is VGA: use
# CONSOLE freebsd-bios, which switches it.)
BOOT_freebsd_amd64       = uefi-amd64
CONSOLE_freebsd_amd64    = freebsd
PKGSCRIPT_freebsd_amd64  = freebsd
PKGCACHE_freebsd_amd64   = freebsd-15.1-amd64
NEEDS_ACCEL_freebsd_amd64 = QEMU/TCG stalls at the boot-loader-to-kernel step (OBS qemu-tcg-x86-64-boot-stall-on-host)

IMAGE_FILE_netbsd_amd64  = NetBSD-11.0-amd64-live.img.gz
IMAGE_COMP_netbsd_amd64  = gz
IMAGE_FMT_netbsd_amd64   = raw
BOOT_netbsd_amd64        = uefi-amd64
# NetBSD's amd64 loader, EFI as well as BIOS, gives the kernel the video
# console: console-netbsd-bios switches it to com0 (and boot.cfg keeps it).
# Its packages are downloaded on the host (host-fetch): the guest's own
# downloads dropped under WHPX, with virtio-net and e1000 alike.
CONSOLE_netbsd_amd64     = netbsd-bios
PKGSCRIPT_netbsd_amd64   = netbsd
PKGCACHE_netbsd_amd64    = netbsd-11.0-amd64
LAYER_SIZE_netbsd_amd64  = 12G
NEEDS_ACCEL_netbsd_amd64 = QEMU/TCG stalls at the boot-loader-to-kernel step (OBS qemu-tcg-x86-64-boot-stall-on-host)

BMAKE_freebsd_arm64 = /usr/bin/make
BMAKE_netbsd_arm64  = /usr/bin/make
BMAKE_freebsd_amd64 = /usr/bin/make
BMAKE_netbsd_amd64  = /usr/bin/make

VM_PLATFORMS = freebsd_arm64 netbsd_arm64 freebsd_amd64 netbsd_amd64 linux_amd64_vm

# --- Windows (the machine running matrix.sh itself, under Cygwin) ---------
# KIND host: build/run-native-host.sh runs the suite right here; HOSTOS is the
# `uname -s` glob the machine must match, else the cell is BLOCKED with that
# reason (harness-windows-host-cells-req). Not in $(PLATFORMS): nothing to
# fetch or provision -- the host is set up by hand (Cygwin packages listed
# in tests/README.md).
KIND_windows_amd64       = host
HOSTOS_windows_amd64     = CYGWIN*
SYSMK_windows_amd64      = /usr/share/bmake/mk
ARCH_windows_amd64       = amd64
TIER_windows_amd64       = 1
TOOLCHAINS_windows_amd64 = llvm gcc msvc
# msvc: run-native-host.sh mounts $(BMK_CACHE)/msvc/EWDK_*.iso read-only and
# passes its drive as BMK_EWDK_ROOT (msvc-ewdk-root-req).

# --- FreeBSD / NetBSD (a BSD machine running matrix.sh itself) -------------
# KIND host as for Windows (harness-bsd-host-cells-req): the suite runs right
# here, with the base system's make (BMAKE -- it has no other name) and its
# mk files; on another host the cells are BLOCKED with the reason. ARCH is
# whatever the machine is. Packages: tests/README.md (FreeBSD: pkgconf gcc
# cmake-core doxygen atf -- clang, make and kyua are in the base system).
KIND_freebsd_host        = host
HOSTOS_freebsd_host      = FreeBSD
SYSMK_freebsd_host       = /usr/share/mk
BMAKE_freebsd_host       = /usr/bin/make
ARCH_freebsd_host        = host
TIER_freebsd_host        = 1
TOOLCHAINS_freebsd_host  = llvm gcc

KIND_netbsd_host         = host
HOSTOS_netbsd_host       = NetBSD
SYSMK_netbsd_host        = /usr/share/mk
BMAKE_netbsd_host        = /usr/bin/make
ARCH_netbsd_host         = host
TIER_netbsd_host         = 2
TOOLCHAINS_netbsd_host   = llvm gcc

# --- Pending, documented only ---------------------------------------------
# windows: tier 1 native MSVC + Cygwin (gcc/llvm), tier 2 mingw-w64 cross.
# Cygwin llvm/gcc now run as KIND host above; MSVC and mingw cells are next.
# mk.toolchain.msvc.mk now exists in the product (this was the actual
# blocker before) -- the remaining gap is test-infrastructure only: no
# Windows VM entry here yet. A genuine amd64 install ISO download was
# started but paused (see harness-scaffolding-predates-frozen-matrix);
# arm64 VM construction was found NOT fully automatable regardless (see
# win-arm64-vm-construction-not-automatable) -- amd64 is the realistic
# path once the ISO download resumes. Not in $(PLATFORMS) until then;
# tracked here so the design accounts for it.
