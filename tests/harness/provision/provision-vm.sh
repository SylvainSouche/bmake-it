#!/bin/sh
# provision-vm.sh <platform-id> <image-path> <ssh-port>
#
# Boots the given VM headless (QEMU), waits for ssh, then installs the
# packages that platform needs (idempotent -- skips if bmake+clang+gcc are
# already present, so re-provisioning after a prior successful run is fast).
# Leaves the VM running afterward -- the build/test phases ssh into it
# directly rather than rebooting per invocation; call vm-shutdown.sh when
# you're done with a platform for this session.
set -eu
PLATFORM="${1:?usage: provision-vm.sh <platform-id> <image-path> <ssh-port>}"
IMAGE="${2:?}"
SSH_PORT="${3:?}"

HARNESS_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
. "$HARNESS_DIR/vm-lib.sh"

PIDFILE="$HOME/.bmk-cache/images/.$PLATFORM.qemu.pid"

if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    echo "provision-vm.sh: $PLATFORM already running (pid $(cat "$PIDFILE")), reusing"
elif vm_wait_ssh "$SSH_PORT" 2 2>/dev/null; then
    echo "provision-vm.sh: $PLATFORM already reachable on port $SSH_PORT (no pidfile -- started outside this script), reusing"
else
    echo "provision-vm.sh: booting $PLATFORM (port $SSH_PORT)..."
    case "$PLATFORM" in
        freebsd_amd64)
            qemu-system-x86_64 -M pc -accel tcg -cpu qemu64 -smp 2 -m 2048 \
                -drive if=virtio,format=qcow2,file="$IMAGE" \
                -device virtio-net-pci,netdev=n0 -netdev "user,id=n0,hostfwd=tcp::${SSH_PORT}-:22" \
                -nographic -serial file:"$HOME/.bmk-cache/images/.$PLATFORM.serial.log" -monitor none -display none \
                >"$HOME/.bmk-cache/images/.$PLATFORM.console.log" 2>&1 &
            echo $! > "$PIDFILE"
            ;;
        netbsd_amd64)
            qemu-system-x86_64 -M pc -accel tcg -cpu qemu64 -smp 2 -m 2048 \
                -drive if=virtio,format=raw,file="$IMAGE" \
                -device virtio-net-pci,netdev=n0 -netdev "user,id=n0,hostfwd=tcp::${SSH_PORT}-:22" \
                -device virtio-rng-pci \
                -nographic -serial file:"$HOME/.bmk-cache/images/.$PLATFORM.serial.log" -monitor none -display none \
                >"$HOME/.bmk-cache/images/.$PLATFORM.console.log" 2>&1 &
            echo $! > "$PIDFILE"
            ;;
        netbsd_arm64)
            EDK2_CODE=$(find /opt/local/share -iname "edk2-aarch64-code.fd" 2>/dev/null | head -1)
            [ -n "$EDK2_CODE" ] || { echo "provision-vm.sh: edk2-aarch64-code.fd not found (port install qemu should provide it)" >&2; exit 2; }
            EDK2_VARS="$HOME/.bmk-cache/images/.$PLATFORM.edk2-vars.fd"
            [ -f "$EDK2_VARS" ] || dd if=/dev/zero of="$EDK2_VARS" bs=1m count=64 2>/dev/null
            qemu-system-aarch64 -M virt,highmem=off -accel hvf -cpu host -smp 2 -m 2560 \
                -drive if=pflash,format=raw,readonly=on,file="$EDK2_CODE" \
                -drive if=pflash,format=raw,file="$EDK2_VARS" \
                -drive if=virtio,format=raw,file="$IMAGE" \
                -device virtio-net-pci,netdev=n0 -netdev "user,id=n0,hostfwd=tcp::${SSH_PORT}-:22" \
                -device virtio-rng-pci \
                -nographic -serial file:"$HOME/.bmk-cache/images/.$PLATFORM.serial.log" -monitor none -display none \
                >"$HOME/.bmk-cache/images/.$PLATFORM.console.log" 2>&1 &
            echo $! > "$PIDFILE"
            ;;
        linux_amd64_vm)
            SEED="$HOME/.bmk-cache/images/.$PLATFORM.seed.iso"
            SEED_DIR=$(mktemp -d)
            cat > "$SEED_DIR/user-data" <<'CLOUDINIT'
#cloud-config
password: bmk
chpasswd:
  expire: false
ssh_pwauth: true
users:
  - name: root
    lock_passwd: false
    shell: /bin/bash
ssh_authorized_keys: []
CLOUDINIT
            printf 'instance-id: bmk\nlocal-hostname: bmk-linux\n' > "$SEED_DIR/meta-data"
            if command -v cloud-localds >/dev/null 2>&1; then
                cloud-localds "$SEED" "$SEED_DIR/user-data" "$SEED_DIR/meta-data"
            else
                genisoimage -output "$SEED" -volid cidata -joliet -rock "$SEED_DIR/user-data" "$SEED_DIR/meta-data" \
                    || mkisofs -output "$SEED" -volid cidata -joliet -rock "$SEED_DIR/user-data" "$SEED_DIR/meta-data"
            fi
            rm -rf "$SEED_DIR"
            qemu-system-x86_64 -M pc -accel tcg -cpu qemu64 -smp 2 -m 2048 \
                -drive if=virtio,format=qcow2,file="$IMAGE" \
                -drive if=virtio,format=raw,file="$SEED",readonly=on \
                -device virtio-net-pci,netdev=n0 -netdev "user,id=n0,hostfwd=tcp::${SSH_PORT}-:22" \
                -nographic -serial file:"$HOME/.bmk-cache/images/.$PLATFORM.serial.log" -monitor none -display none \
                >"$HOME/.bmk-cache/images/.$PLATFORM.console.log" 2>&1 &
            echo $! > "$PIDFILE"
            ;;
        *)
            echo "provision-vm.sh: unknown platform '$PLATFORM'" >&2
            exit 2
            ;;
    esac
    echo "provision-vm.sh: waiting for ssh..."
    vm_wait_ssh "$SSH_PORT" 240
fi

echo "provision-vm.sh: installing packages on $PLATFORM..."
case "$PLATFORM" in
    freebsd_amd64)
        vm_ssh "$SSH_PORT" 'command -v clang >/dev/null && command -v gcc >/dev/null' \
            || vm_ssh "$SSH_PORT" 'ASSUME_ALWAYS_YES=yes pkg install -y gcc llvm file'
        ;;
    netbsd_amd64|netbsd_arm64)
        vm_ssh "$SSH_PORT" 'command -v clang >/dev/null && command -v gcc >/dev/null' \
            || vm_ssh "$SSH_PORT" 'PKG_PATH="https://cdn.NetBSD.org/pub/pkgsrc/packages/NetBSD/$(uname -p)/10.1/All" pkg_add -v clang gcc12 file' \
            || echo "provision-vm.sh: WARNING -- automatic pkg_add failed, may need manual bootstrap (see NetBSD-arm64 setup notes from earlier this session)" >&2
        ;;
    linux_amd64_vm)
        vm_ssh "$SSH_PORT" 'command -v clang >/dev/null && command -v gcc >/dev/null && command -v bmake >/dev/null' \
            || vm_ssh "$SSH_PORT" 'apt-get update -qq && apt-get install -y -qq bmake clang lld gcc file'
        ;;
esac

echo "provision-vm.sh: $PLATFORM ready on port $SSH_PORT"
