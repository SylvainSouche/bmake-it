#!/bin/sh
# vm.sh <command> [platform-id] -- lifecycle of the harness's QEMU guests.
#
#   fetch     <id>   download the published image into $BMK_CACHE/images
#   prepare   <id>   decompress it into a read-only base ($BMK_DISKS/base)
#   provision <id>   boot the base once, install the harness ssh key and
#                    enable sshd over the serial console, shut down; the
#                    result is the provisioned layer ($BMK_DISKS/layers)
#   rebuild   <id>   delete the provisioned layer and provision again
#   up        <id>   boot a fresh disposable overlay on the layer; wait for ssh
#   down      <id>   graceful guest shutdown
#   reset     <id>   down, then delete the overlay (the layer is untouched)
#   sysroot   <id> [dest.tar]  tar the guest's own headers and libraries as a
#                    cross-compilation sysroot (default $BMK_CACHE/sysroots/<os>-<arch>.tar);
#                    taken from the guest so it matches the OS the binary will run on
#   ssh       <id> [command...]
#   status    [id]   what exists for each VM platform
#
# Disks are layered (harness-vm-layers-req): base <- layer <- run overlay.
# base <- layer is stored relative, so $BMK_CACHE can be moved; a run overlay
# is disposable and names its layer absolutely (`vm.sh reset` after a move).
# What a platform needs comes from platforms.mk (IMAGE_*, BOOT_*, MEM_*, ...).
# @impl 0f87-6ad7-1929-a1bb
set -eu
HARNESS_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
. "$HARNESS_DIR/lib/env.sh"
. "$HARNESS_DIR/vm-lib.sh"

die() { echo "vm.sh: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "'$1' not found (see docs/spec/05-setup-and-administration.md)"; }

load() { # load <id>: the platform's fields into shell variables
    ID=$1
    [ "$(plat "$ID" KIND)" = vm ] || die "'$ID' is not a vm platform in platforms.mk"
    ARCH=$(plat "$ID" ARCH);          URL=$(plat "$ID" IMAGE_URL)
    FILE=$(plat "$ID" IMAGE_FILE);    COMP=$(plat "$ID" IMAGE_COMP)
    FMT=$(plat "$ID" IMAGE_FMT);      BOOT=$(plat "$ID" BOOT)
    PORT=$(plat "$ID" SSH_PORT);      MEM=$(plat "$ID" MEM)
    CONSOLE=$(plat "$ID" CONSOLE);    BLOCKED=$(plat "$ID" BLOCKED)
    PKGSCRIPT=$(plat "$ID" PKGSCRIPT); LAYER_SIZE=$(plat "$ID" LAYER_SIZE)
    MEM=${MEM:-2048}
    BASE="$BMK_DISKS/base/$ID.$FMT"; LAYER="$BMK_DISKS/layers/$ID.qcow2"
    RUNDIR="$BMK_VMS/$ID";     SOCKDIR="$BMK_RUN/$ID"
    PIDFILE="$SOCKDIR/qemu.pid";     SOCK="$SOCKDIR/console.sock"
    KEY="$BMK_CACHE/keys/harness_ed25519"
    HARNESS_KEY="$KEY"; export HARNESS_KEY
}

running() { [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; }

# wait_ssh_or_exit <seconds>: 0 = ssh answers, 2 = qemu exited (the guest
# rebooted; QEMU runs with -no-reboot so a reboot is a cold start, never an
# in-guest warm reset, which hangs NetBSD under hvf), 1 = neither in time.
wait_ssh_or_exit() {
    n=0
    while [ "$n" -lt "$1" ]; do
        running || return 2
        vm_wait_ssh "$PORT" 3 2>/dev/null && return 0
        n=$((n + 3))
    done
    return 1
}

fetch() {
    mkdir -p "$BMK_CACHE/images"
    [ -f "$BMK_CACHE/images/$FILE" ] && { echo "have $FILE"; return 0; }
    echo "fetching $URL"
    curl -fL -C - --retry 5 --retry-delay 5 -o "$BMK_CACHE/images/.$FILE.part" "$URL"
    mv "$BMK_CACHE/images/.$FILE.part" "$BMK_CACHE/images/$FILE"
}

prepare() {
    [ -f "$BASE" ] && return 0
    [ -f "$BMK_CACHE/images/$FILE" ] || fetch
    mkdir -p "$BMK_DISKS/base"
    echo "preparing $BASE"
    case "$COMP" in
        xz)   need xz;   xz -dc "$BMK_CACHE/images/$FILE" > "$BASE.tmp" ;;
        gz)   need gzip; gzip -dc "$BMK_CACHE/images/$FILE" > "$BASE.tmp" ;;
        none) cp "$BMK_CACHE/images/$FILE" "$BASE.tmp" ;;
        *)    die "$ID: IMAGE_COMP '$COMP' unknown" ;;
    esac
    mv "$BASE.tmp" "$BASE"; chmod a-w "$BASE"
}

accel() { # guest arch vs host: hardware acceleration only when they match
    host=$(uname -m); [ "$host" = aarch64 ] && host=arm64; [ "$host" = x86_64 ] && host=amd64
    if [ "$host" = "$ARCH" ]; then
        case "$(uname -s)" in Darwin) echo hvf ;; Linux) echo kvm ;; *) echo tcg ;; esac
    else echo tcg; fi
}

boot() { # boot <disk-file> <disk-format>  -- starts qemu in the background
    disk=$1; dfmt=$2
    [ -z "$BLOCKED" ] || die "$ID is blocked: $BLOCKED"
    if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
        die "ssh port $PORT is already in use (a stale qemu? see: lsof -nP -iTCP:$PORT)"
    fi
    mkdir -p "$SOCKDIR" "$RUNDIR"; rm -f "$SOCK"
    A=$(accel)
    case "$BOOT" in
        uefi-arm64)
            need qemu-system-aarch64
            code=$(find /opt/local/share /usr/share /usr/local/share /opt/homebrew/share -name edk2-aarch64-code.fd 2>/dev/null | head -1)
            [ -n "$code" ] || die "edk2-aarch64-code.fd not found (install qemu's firmware)"
            [ -f "$RUNDIR/vars.fd" ] || dd if=/dev/zero of="$RUNDIR/vars.fd" bs=1048576 count=64 2>/dev/null
            cpu=host; [ "$A" = tcg ] && cpu=max
            set -- qemu-system-aarch64 -M virt,highmem=off -accel "$A" -cpu "$cpu" -smp 2 -m "$MEM" \
                -drive if=pflash,format=raw,readonly=on,file="$code" \
                -drive if=pflash,format=raw,file="$RUNDIR/vars.fd" ;;
        bios-amd64)
            need qemu-system-x86_64
            cpu=host; [ "$A" = tcg ] && cpu=qemu64
            set -- qemu-system-x86_64 -M pc -accel "$A" -cpu "$cpu" -smp 2 -m "$MEM" ;;
        *) die "$ID: BOOT '$BOOT' unknown" ;;
    esac
    "$@" -drive if=virtio,format="$dfmt",file="$disk" \
        -device virtio-net-pci,netdev=n0 -netdev "user,id=n0,hostfwd=tcp::${PORT}-:22" \
        -device virtio-rng-pci -nographic \
        -chardev "socket,id=ser0,path=$SOCK,server=on,wait=off,logfile=$SOCKDIR/console.log" \
        -serial chardev:ser0 -no-reboot -monitor none -display none \
        >"$SOCKDIR/qemu.log" 2>&1 &
    echo $! > "$PIDFILE"
    sleep 1
    running || { cat "$SOCKDIR/qemu.log" >&2; die "qemu did not start"; }
}

provision() {
    [ -f "$LAYER" ] && { echo "have layer for $ID"; return 0; }
    [ -n "$CONSOLE" ] || die "$ID has no CONSOLE script in platforms.mk"
    prepare
    need qemu-img; need python3
    mkdir -p "$BMK_DISKS/layers" "$BMK_CACHE/keys"
    [ -f "$KEY" ] || ssh-keygen -q -t ed25519 -N '' -C bmk-harness -f "$KEY"
    tmp="$BMK_DISKS/layers/.$ID.qcow2.tmp"; rm -f "$tmp"
    ( cd "$BMK_DISKS/layers" && qemu-img create -q -f qcow2 -b "../base/$ID.$FMT" -F "$FMT" ".$ID.qcow2.tmp" ${LAYER_SIZE:+"$LAYER_SIZE"} )
    rm -rf "$RUNDIR"; echo "provisioning $ID over its serial console (once)..."
    boot "$tmp" qcow2
    # Some images reboot themselves early in their first boot (NetBSD grows
    # its root filesystem); QEMU then exits (-no-reboot), and the console
    # script is simply run again against the next, cold boot.
    n=0
    until sed "s|@PUBKEY@|$(cat "$KEY.pub")|" "$HARNESS_DIR/provision/console-$CONSOLE.txt" \
            | python3 "$HARNESS_DIR/lib/console.py" "$SOCK" >"$SOCKDIR/provision.log" 2>&1; do
        if running; then
            tail -20 "$SOCKDIR/provision.log" >&2; kill "$(cat "$PIDFILE")"
            die "console provisioning failed (see $SOCKDIR/console.log)"
        fi
        n=$((n + 1)); [ "$n" -le 4 ] || die "guest keeps exiting during console provisioning (see $SOCKDIR/console.log)"
        echo "guest exited during its first boot; starting it again ($n)..."
        boot "$tmp" qcow2
    done
    # The provisioning step may reboot the guest more than once (NetBSD grows
    # its root filesystem across reboots): start it again each time it exits.
    tries=0
    while :; do
        rc=0; wait_ssh_or_exit 240 || rc=$?
        [ "$rc" -eq 0 ] && break
        [ "$rc" -eq 2 ] || die "sshd not reachable after provisioning (see $SOCKDIR/console.log)"
        tries=$((tries + 1)); [ "$tries" -le 4 ] || die "guest keeps rebooting (see $SOCKDIR/console.log)"
        echo "guest rebooted; starting it again ($tries)..."
        boot "$tmp" qcow2
    done
    if [ -n "$PKGSCRIPT" ]; then
        echo "installing packages (provision/packages-$PKGSCRIPT.sh)..."
        vm_ssh "$PORT" "sh -s" <"$HARNESS_DIR/provision/packages-$PKGSCRIPT.sh" >"$SOCKDIR/packages.log" 2>&1 \
            || { tail -20 "$SOCKDIR/packages.log" >&2; vm_shutdown "$PORT" "$(cat "$PIDFILE")"; die "package install failed"; }
    fi
    vm_shutdown "$PORT" "$(cat "$PIDFILE")"
    rm -rf "$RUNDIR" "$SOCKDIR"
    mv "$tmp" "$LAYER"; chmod a-w "$LAYER"
    echo "provisioned layer: $LAYER"
}

up() {
    running && { echo "$ID already running"; return 0; }
    provision
    mkdir -p "$RUNDIR"
    [ -f "$RUNDIR/disk.qcow2" ] || ( cd "$RUNDIR" && qemu-img create -q -f qcow2 -b "$LAYER" -F qcow2 disk.qcow2 )
    boot "$RUNDIR/disk.qcow2" qcow2
    vm_wait_ssh "$PORT" 240 || die "$ID: no ssh within 240 s (see $SOCKDIR/qemu.log)"
    echo "$ID up (ssh port $PORT)"
}

down() {
    running || { echo "$ID not running"; return 0; }
    vm_shutdown "$PORT" "$(cat "$PIDFILE")"; rm -rf "$SOCKDIR"; echo "$ID down"
}

status_one() {
    load "$1"
    s=""
    [ -f "$BMK_CACHE/images/$FILE" ] && s="$s image" || s="$s -"
    [ -f "$BASE" ] && s="$s base" || s="$s -"
    [ -f "$LAYER" ] && s="$s layer" || s="$s -"
    running && s="$s RUNNING" || s="$s stopped"
    [ -n "$BLOCKED" ] && s="$s  BLOCKED: $BLOCKED"
    printf '%-16s %s\n' "$ID" "$s"
}

cmd=${1:-}; shift || true
case "$cmd" in
    status)
        if [ $# -gt 0 ]; then status_one "$1"; else
            printf '%-16s %s\n' platform "image base layer state"
            for p in $(printf 'include %s/platforms.mk\n_x:\n\t@echo $(VM_PLATFORMS)\n' "$HARNESS_DIR" | make -s -f - _x); do status_one "$p"; done
        fi ;;
    fetch|prepare|provision|rebuild|up|down|ssh|reset|sysroot)
        [ $# -ge 1 ] || die "usage: vm.sh $cmd <platform-id>"
        load "$1"; shift
        case "$cmd" in
            fetch) fetch ;; prepare) prepare ;; provision) provision ;; up) up ;;
            rebuild) down; chmod u+w "$LAYER" 2>/dev/null || true; rm -rf "$LAYER" "$RUNDIR"; provision ;;
            down) down ;;
            reset) down; rm -rf "$RUNDIR"; echo "$ID reset (overlay deleted)" ;;
            ssh) vm_ssh "$PORT" "$@" ;;
            sysroot)
                os=${ID%%_*}; arch=${ID##*_}
                dest=${1:-$BMK_CACHE/sysroots/$os-$arch.tar}
                running || die "$ID is not running (vm.sh up $ID first)"
                case "$os" in
                    freebsd) paths="usr/include usr/lib lib" ;;
                    netbsd)  paths="usr/include usr/lib lib libexec/ld.elf_so" ;;
                    *) die "no sysroot recipe for '$os' (Linux sysroots come from fetch/build-sysroot-linux.sh)" ;;
                esac
                mkdir -p "$(dirname "$dest")"
                vm_ssh "$PORT" "cd / && tar --exclude usr/lib/debug --exclude usr/lib32 -cf - $paths" > "$dest.tmp" && mv "$dest.tmp" "$dest"
                echo "sysroot: $dest ($(du -h "$dest" | cut -f1))" ;;
        esac ;;
    *) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
