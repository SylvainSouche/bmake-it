#!/bin/sh
# run-matrix.sh — automated cross-platform test matrix for Bmake It.
#
# Runs the packaged unit-test suite (tests/archives/*.tar.gz, built by
# pack-cases.sh) natively on every supported platform, plus a smoke build
# of examples/myworkspace/Hello for every cross-compilation direction.
#
# Native jobs (full 27-case suite via run-tests.sh):
#   linux-glibc   Debian container (docker), host arch
#   linux-musl    Alpine container (docker), host arch
#   linux-amd64   Debian container (docker), forced --platform linux/amd64
#                 via qemu-user emulation -- the one native amd64 data point
#                 when every other native job in this matrix runs on arm64
#   macos         this host, only when run ON macOS
#   netbsd        an already-booted NetBSD VM reachable over ssh
#
# Cross-compile smoke jobs (build Hello, verify the output file format):
#   linux->freebsd        BMK_FREEBSD_SYSROOT (a FreeBSD base.txz extract)
#   linux->macos          BMK_MACOS_SYSROOT (a local Xcode SDK extract)
#   netbsd->linux         BMK_LINUX_SYSROOT, run *inside* the NetBSD VM
#   linux/arm64->amd64    BMK_LINUX_AMD64_SYSROOT (a .tar, like
#                         BMK_MACOS_SYSROOT -- extracted inside the
#                         container, never onto the macOS host filesystem).
#                         Same OS, cross ARCH; the output is also actually
#                         executed, via --platform linux/amd64 qemu-user
#                         emulation, not just file(1)-checked
#
# Each job is independent and best-effort: a missing prerequisite (no
# docker, no VM reachable, no sysroot staged) SKIPs that job with a reason
# instead of failing the whole run. Exit status is nonzero only if a job
# that DID run reported a failure.
#
# Sysroots are never bundled or fetched by this script -- see
# scripts/prep-*-sysroot.sh for how to stage each one. Point this script at
# existing staged sysroots via:
#   BMK_FREEBSD_SYSROOT=/path/to/freebsd-sysroot
#   BMK_LINUX_SYSROOT=/path/to/linux-sysroot   (used for linux->freebsd's
#                                                 *host* linux container AND
#                                                 to tell it where to find a
#                                                 Linux sysroot for other jobs)
#   BMK_MACOS_SYSROOT=/path/to/MacOSX.sdk
#   NETBSD_VM_SSH=root@localhost -p 2222        (ssh target for the netbsd
#                                                 VM; must already be booted
#                                                 with the impl tree and a
#                                                 Linux sysroot staged --
#                                                 see prep-netbsd-vm.sh)
#
# Usage: run-matrix.sh [job ...]     (default: run every job that has its
#                                      prerequisites available)
# Jobs:  linux-glibc linux-musl linux-amd64 macos netbsd
#        cross-linux-freebsd cross-linux-macos cross-netbsd-linux
#        cross-linux-arm64-amd64

set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
TESTS_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
BMK_ROOT=$(CDPATH= cd -- "$TESTS_ROOT/.." && pwd)
ARCHIVES_DIR="$TESTS_ROOT/archives"

BMK_FREEBSD_SYSROOT="${BMK_FREEBSD_SYSROOT:-}"
BMK_LINUX_SYSROOT="${BMK_LINUX_SYSROOT:-}"
BMK_LINUX_AMD64_SYSROOT="${BMK_LINUX_AMD64_SYSROOT:-}"
BMK_MACOS_SYSROOT="${BMK_MACOS_SYSROOT:-}"
NETBSD_VM_SSH="${NETBSD_VM_SSH:-root@localhost -p 2222}"

ALL_JOBS="linux-glibc linux-musl linux-amd64 macos netbsd cross-linux-freebsd cross-linux-macos cross-netbsd-linux cross-linux-arm64-amd64"
JOBS="${*:-$ALL_JOBS}"

RESULTS_FILE=$(mktemp "${TMPDIR:-/tmp}/bmk-matrix.XXXXXX")
trap 'rm -f "$RESULTS_FILE"' EXIT INT TERM

record() { printf '%-24s %-6s %s\n' "$1" "$2" "$3" >>"$RESULTS_FILE"; }

log()  { printf '\n=== %s ===\n' "$1"; }
have() { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
# native docker-based jobs (linux-glibc, linux-musl)
# ---------------------------------------------------------------------------
run_docker_native() {
    job="$1" image="$2" pkgcmd="$3" platform="${4:-}"
    log "$job (docker: $image${platform:+, --platform $platform})"
    if ! have docker || ! docker info >/dev/null 2>&1; then
        record "$job" SKIP "docker not available/running"
        return
    fi
    # Colima only bind-mounts $HOME by default, not /tmp or /Users/Shared --
    # stage under $HOME so the container can actually see the files.
    stage=$(mktemp -d "$HOME/.bmk-stage.XXXXXX")
    cp -R "$BMK_ROOT"/. "$stage/" 2>/dev/null
    # A non-host --platform runs under qemu-user emulation (binfmt_misc) --
    # confirmed working (compiles and runs a genuine x86_64 ELF) but slow;
    # give it more room than a native-arch container needs.
    out=$(docker run --rm ${platform:+--platform "$platform"} -v "$stage:/work" "$image" sh -c "
        set -e
        $pkgcmd >/dev/null 2>&1
        cd /work/tests/harness
        BMK_MKDIR=/work/mk BMK_SCRIPTS=/work/scripts sh ./run-tests.sh
    " 2>&1)
    status=$?
    rm -rf "$stage"
    printf '%s\n' "$out"
    if [ $status -eq 0 ]; then
        summary=$(printf '%s\n' "$out" | grep -E '^(pass|fail|skip|error)=' | tr '\n' ' ')
        record "$job" PASS "$summary"
    else
        record "$job" FAIL "exit $status"
    fi
}

job_linux_glibc() {
    # gcc is needed too: the suite includes a TOOLCHAIN=gcc test case
    # (target-key naming), independent of the default TOOLCHAIN=llvm build.
    run_docker_native linux-glibc debian:bookworm-slim \
        "apt-get update -qq && apt-get install -y -qq bmake clang lld gcc"
}

job_linux_musl() {
    # gcc is required here even though TOOLCHAIN=llvm is what actually
    # compiles: Alpine's clang package has no working default linker on its
    # own (no crt objects/libgcc) -- found empirically ("posix_spawn failed"
    # on link). Installing gcc pulls in the runtime objects clang needs.
    run_docker_native linux-musl alpine:latest \
        "apk add --no-cache bmake clang lld gcc musl-dev >/dev/null"
}

job_linux_amd64() {
    # Runs under qemu-user emulation on an arm64 host (Colima ships
    # binfmt_misc registration for this) -- every other native job in this
    # matrix happens to run on arm64 (arm64 host, arm64 containers, arm64
    # NetBSD VM), so this is the one native amd64 data point, confirming the
    # host-arch-detection path isn't only ever exercised on one arch.
    run_docker_native linux-amd64 debian:bookworm-slim \
        "apt-get update -qq && apt-get install -y -qq bmake clang lld gcc" \
        linux/amd64
}

# ---------------------------------------------------------------------------
# native macOS job (this host, only if actually macOS)
# ---------------------------------------------------------------------------
job_macos() {
    log "macos (native, this host)"
    if [ "$(uname -s)" != "Darwin" ]; then
        record macos SKIP "host is not macOS"
        return
    fi
    if ! have bmake; then
        record macos SKIP "bmake not on PATH (MacPorts: port install bmake)"
        return
    fi
    out=$(cd "$TESTS_ROOT/harness" && BMK_MKDIR="$BMK_ROOT/mk" BMK_SCRIPTS="$BMK_ROOT/scripts" sh ./run-tests.sh 2>&1)
    status=$?
    printf '%s\n' "$out"
    if [ $status -eq 0 ]; then
        summary=$(printf '%s\n' "$out" | grep -E '^(pass|fail|skip|error)=' | tr '\n' ' ')
        record macos PASS "$summary"
    else
        record macos FAIL "exit $status"
    fi
}

# ---------------------------------------------------------------------------
# native NetBSD job (over ssh into an already-booted VM)
# ---------------------------------------------------------------------------
netbsd_ssh() {
    # shellcheck disable=SC2086
    ssh -F /dev/null -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=5 $NETBSD_VM_SSH "$@"
}

job_netbsd() {
    log "netbsd (native, via ssh: $NETBSD_VM_SSH)"
    if ! netbsd_ssh 'true' >/dev/null 2>&1; then
        record netbsd SKIP "VM not reachable at $NETBSD_VM_SSH"
        return
    fi
    # Sync current tree onto the VM. COPYFILE_DISABLE + --no-xattrs avoids
    # AppleDouble ._foo sidecars (macOS quarantine xattrs) turning into real
    # files on the far end -- see pack-cases.sh for the same fix.
    sync_err=$(mktemp "${TMPDIR:-/tmp}/Bmake It-sync.XXXXXX")
    if ! (
        export COPYFILE_DISABLE=1
        tar --no-xattrs --no-acls --no-mac-metadata -C "$BMK_ROOT" -cf - mk scripts tests/harness tests/cases 2>/dev/null \
            || tar -C "$BMK_ROOT" -cf - mk scripts tests/harness tests/cases
    ) | netbsd_ssh 'rm -rf /root/impl-matrix && mkdir -p /root/impl-matrix && tar -C /root/impl-matrix -xf -' >"$sync_err" 2>&1; then
        record netbsd SKIP "failed to sync tree to VM: $(tail -3 "$sync_err" | tr '\n' ' ')"
        rm -f "$sync_err"
        return
    fi
    rm -f "$sync_err"
    out=$(netbsd_ssh '
        cd /root/impl-matrix/tests/harness
        sh pack-cases.sh >/dev/null 2>&1
        BMK_MKDIR=/root/impl-matrix/mk BMK_SCRIPTS=/root/impl-matrix/scripts BMAKE=/usr/bin/make sh ./run-tests.sh
    ' 2>&1)
    status=$?
    printf '%s\n' "$out"
    if [ $status -eq 0 ]; then
        summary=$(printf '%s\n' "$out" | grep -E '^(pass|fail|skip|error)=' | tr '\n' ' ')
        record netbsd PASS "$summary"
    else
        record netbsd FAIL "exit $status"
    fi
}

# ---------------------------------------------------------------------------
# cross-compile smoke jobs: build examples/myworkspace/Hello, check output
# ---------------------------------------------------------------------------
job_cross_linux_freebsd() {
    log "cross: linux -> freebsd (docker)"
    if ! have docker || ! docker info >/dev/null 2>&1; then
        record cross-linux-freebsd SKIP "docker not available/running"
        return
    fi
    if [ -z "$BMK_FREEBSD_SYSROOT" ] || [ ! -d "$BMK_FREEBSD_SYSROOT" ]; then
        record cross-linux-freebsd SKIP "BMK_FREEBSD_SYSROOT not set/found (see scripts/prep-freebsd-sysroot.sh)"
        return
    fi
    stage=$(mktemp -d "$HOME/.bmk-stage.XXXXXX")
    cp -R "$BMK_ROOT"/. "$stage/" 2>/dev/null
    out=$(docker run --rm -v "$stage:/work" -v "$BMK_FREEBSD_SYSROOT:/sysroot:ro" \
        debian:bookworm-slim sh -c "
        set -e
        apt-get update -qq >/dev/null && apt-get install -y -qq bmake clang lld file >/dev/null
        cd /work/examples/myworkspace/Hello
        export BMK_MKDIR=/work/mk MAKESYSPATH=/work/mk:/usr/share/mk
        export BMK_FREEBSD_SYSROOT=/sysroot
        bmake TARGET=freebsd TARGET_ARCH=amd64
        file build/freebsd-amd64/bin/hello
    " 2>&1)
    status=$?
    rm -rf "$stage"
    printf '%s\n' "$out"
    if [ $status -eq 0 ] && printf '%s' "$out" | grep -qi 'FreeBSD'; then
        record cross-linux-freebsd PASS "genuine FreeBSD ELF produced"
    else
        record cross-linux-freebsd FAIL "exit $status / output not FreeBSD ELF"
    fi
}

job_cross_linux_macos() {
    log "cross: linux -> macos (docker)"
    if ! have docker || ! docker info >/dev/null 2>&1; then
        record cross-linux-macos SKIP "docker not available/running"
        return
    fi
    if [ -z "$BMK_MACOS_SYSROOT" ] || [ ! -f "$BMK_MACOS_SYSROOT" ] && [ ! -d "$BMK_MACOS_SYSROOT" ]; then
        record cross-linux-macos SKIP "BMK_MACOS_SYSROOT not set/found (see scripts/prep-macos-sysroot.sh)"
        return
    fi
    stage=$(mktemp -d "$HOME/.bmk-stage.XXXXXX")
    cp -R "$BMK_ROOT"/. "$stage/" 2>/dev/null
    sdkmount="$BMK_MACOS_SYSROOT"
    sdktar_arg=""
    if [ -f "$BMK_MACOS_SYSROOT" ]; then
        # a tarball -- mount read-only and extract inside the container
        sdktar_arg="-v $BMK_MACOS_SYSROOT:/macos-sdk.tar:ro"
        sdkmount=""
    fi
    out=$(docker run --rm -v "$stage:/work" $sdktar_arg \
        ${sdkmount:+-v "$sdkmount:/sdk-dir:ro"} \
        debian:bookworm-slim sh -c "
        set -e
        apt-get update -qq >/dev/null && apt-get install -y -qq bmake clang-22 lld-22 file >/dev/null 2>&1
        # Debian bookworm ships clang only as the versioned clang-22 package
        # (needed here for TBD/-platform_version compatibility with a recent
        # macOS SDK -- see mk.toolchain.llvm.mk). Symlink the unversioned
        # names so the project's normal PATH-based CC resolution finds it at
        # every recursion level -- a CC= override on the top-level bmake
        # invocation is NOT forwarded to recursive submodule builds (only
        # TARGET/TARGET_ARCH/TOOLCHAIN are, in mk.framework.mk), so relying
        # on an override here would silently fall through to no-compiler in
        # nested module builds instead of erroring loudly.
        ln -sf /usr/bin/clang-22 /usr/bin/clang
        ln -sf /usr/bin/clang++-22 /usr/bin/clang++
        if [ -f /macos-sdk.tar ]; then mkdir -p /sdk && tar -xf /macos-sdk.tar -C /sdk && SDKROOT=/sdk/MacOSX.sdk; else SDKROOT=/sdk-dir; fi
        cd /work/examples/myworkspace/Hello
        export BMK_MKDIR=/work/mk MAKESYSPATH=/work/mk:/usr/share/mk
        export BMK_MACOS_SYSROOT=\$SDKROOT
        bmake TARGET=macos TARGET_ARCH=arm64
        file build/macos-arm64/bin/hello
    " 2>&1)
    status=$?
    rm -rf "$stage"
    printf '%s\n' "$out"
    if [ $status -eq 0 ] && printf '%s' "$out" | grep -qi 'Mach-O'; then
        record cross-linux-macos PASS "genuine Mach-O arm64 executable produced"
    else
        record cross-linux-macos FAIL "exit $status / output not Mach-O"
    fi
}

job_cross_netbsd_linux() {
    log "cross: netbsd -> linux (via ssh into VM)"
    if ! netbsd_ssh 'true' >/dev/null 2>&1; then
        record cross-netbsd-linux SKIP "VM not reachable at $NETBSD_VM_SSH"
        return
    fi
    if ! netbsd_ssh 'test -d /root/linux-sysroot/sysroot' >/dev/null 2>&1; then
        record cross-netbsd-linux SKIP "no Linux sysroot staged on VM at /root/linux-sysroot/sysroot (see scripts/prep-linux-sysroot.sh)"
        return
    fi
    (
        export COPYFILE_DISABLE=1
        tar --no-xattrs --no-acls --no-mac-metadata -C "$BMK_ROOT" -cf - mk scripts examples 2>/dev/null \
            || tar -C "$BMK_ROOT" -cf - mk scripts examples
    ) | netbsd_ssh 'rm -rf /root/impl-matrix-cross && mkdir -p /root/impl-matrix-cross && tar -C /root/impl-matrix-cross -xf -' 2>/dev/null
    out=$(netbsd_ssh '
        cd /root/impl-matrix-cross/examples/myworkspace/Hello
        export BMK_MKDIR=/root/impl-matrix-cross/mk MAKESYSPATH=/root/impl-matrix-cross/mk:/usr/share/mk
        export BMK_LINUX_SYSROOT=/root/linux-sysroot/sysroot
        /usr/bin/make TARGET=linux TARGET_ARCH=aarch64
        file build/linux-aarch64/bin/hello
    ' 2>&1)
    status=$?
    printf '%s\n' "$out"
    if [ $status -eq 0 ] && printf '%s' "$out" | grep -qi 'ELF'; then
        record cross-netbsd-linux PASS "genuine Linux ELF produced (run it on real Linux to fully verify)"
    else
        record cross-netbsd-linux FAIL "exit $status / output not Linux ELF"
    fi
}

job_cross_linux_arm64_amd64() {
    # Same OS, cross ARCH -- built on an arm64 Linux container, targeting
    # amd64 Linux. Unlike the other cross jobs, the amd64 output can also
    # actually be *run* here (not just file(1)-checked): qemu-user
    # emulation for --platform linux/amd64 is already confirmed working.
    log "cross: linux/arm64 -> linux/amd64 (docker)"
    if ! have docker || ! docker info >/dev/null 2>&1; then
        record cross-linux-arm64-amd64 SKIP "docker not available/running"
        return
    fi
    if [ -z "$BMK_LINUX_AMD64_SYSROOT" ] || [ ! -f "$BMK_LINUX_AMD64_SYSROOT" ]; then
        record cross-linux-arm64-amd64 SKIP "BMK_LINUX_AMD64_SYSROOT not set/found -- a .tar of an amd64 Linux sysroot (usr/include, usr/lib/x86_64-linux-gnu, usr/lib/gcc/x86_64-linux-gnu, and a REAL non-symlink /lib64/ld-linux-x86-64.so.2). Kept as a tar and extracted inside the container, same as BMK_MACOS_SYSROOT -- extracting Linux headers directly onto macOS's case-insensitive filesystem corrupts them (see scripts/prep-linux-sysroot.sh)."
        return
    fi
    stage=$(mktemp -d "$HOME/.bmk-stage.XXXXXX")
    cp -R "$BMK_ROOT"/. "$stage/" 2>/dev/null
    out=$(docker run --rm -v "$stage:/work" -v "$BMK_LINUX_AMD64_SYSROOT:/sysroot.tar:ro" \
        debian:bookworm-slim sh -c "
        set -e
        uname -m
        apt-get update -qq >/dev/null && apt-get install -y -qq bmake clang lld file >/dev/null 2>&1
        mkdir -p /sysroot && tar -xf /sysroot.tar -C /sysroot
        cd /work/examples/myworkspace/Hello
        export BMK_MKDIR=/work/mk MAKESYSPATH=/work/mk:/usr/share/mk
        export BMK_LINUX_SYSROOT=/sysroot
        bmake TARGET=linux TARGET_ARCH=amd64
        file build/linux-amd64/bin/hello
    " 2>&1)
    status=$?
    printf '%s\n' "$out"
    if [ $status -ne 0 ] || ! printf '%s' "$out" | grep -qi 'x86-64'; then
        rm -rf "$stage"
        record cross-linux-arm64-amd64 FAIL "exit $status / output not x86-64 ELF"
        return
    fi
    # Actually run it, under --platform linux/amd64 emulation, not just
    # inspect the file format.
    run_out=$(docker run --rm --platform linux/amd64 \
        -v "$stage/examples/myworkspace/Hello:/hello:ro" debian:bookworm-slim sh -c '
        export LD_LIBRARY_PATH=/hello/hello.m/../build/linux-amd64/lib
        /hello/hello.m/build/linux-amd64/bin/hello
    ' 2>&1)
    run_status=$?
    rm -rf "$stage"
    printf '%s\n' "$run_out"
    if [ $run_status -eq 0 ] && printf '%s' "$run_out" | grep -q 'Hello, Bmake It!'; then
        record cross-linux-arm64-amd64 PASS "genuine x86-64 ELF produced AND executed under emulation"
    else
        record cross-linux-arm64-amd64 FAIL "built but did not run cleanly (exit $run_status)"
    fi
}

# ---------------------------------------------------------------------------
# dispatch
# ---------------------------------------------------------------------------
for j in $JOBS; do
    case "$j" in
        linux-glibc)         job_linux_glibc ;;
        linux-amd64)          job_linux_amd64 ;;
        linux-musl)           job_linux_musl ;;
        macos)                job_macos ;;
        netbsd)                job_netbsd ;;
        cross-linux-freebsd)  job_cross_linux_freebsd ;;
        cross-linux-macos)    job_cross_linux_macos ;;
        cross-netbsd-linux)   job_cross_netbsd_linux ;;
        cross-linux-arm64-amd64) job_cross_linux_arm64_amd64 ;;
        *) echo "unknown job: $j (see header comment for the list)" >&2 ;;
    esac
done

log "matrix summary"
cat "$RESULTS_FILE"

if grep -q '	*FAIL' "$RESULTS_FILE" 2>/dev/null || awk '{print $2}' "$RESULTS_FILE" | grep -q '^FAIL$'; then
    exit 1
fi
exit 0
