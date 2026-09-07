#!/bin/sh
# provision-macos-vm.sh
#
# Clones a fresh instance from the pulled Cirrus Labs macOS base image,
# boots it (Virtualization.framework via tart), waits for it to come up,
# then installs MacPorts + bmake + gcc + llvm over ssh -- same pattern as
# the other VM platforms, just using `tart` instead of raw QEMU since
# Apple's Virtualization.framework (not QEMU) is what can boot a macOS
# guest at all on Apple Silicon.
set -eu

BASE_IMAGE="ghcr.io/cirruslabs/macos-sequoia-base:latest"
VM_NAME="bmk-macos"

if ! tart list 2>/dev/null | grep -q "^${VM_NAME}"; then
    echo "provision-macos-vm.sh: cloning $BASE_IMAGE -> $VM_NAME"
    tart clone "$BASE_IMAGE" "$VM_NAME"
fi

if ! tart list 2>/dev/null | grep "^${VM_NAME}" | grep -q running; then
    echo "provision-macos-vm.sh: starting $VM_NAME"
    tart run "$VM_NAME" --no-graphics &
    disown
    sleep 5
fi

echo "provision-macos-vm.sh: waiting for IP..."
IP=""
n=0
while [ -z "$IP" ] && [ "$n" -lt 60 ]; do
    IP=$(tart ip "$VM_NAME" 2>/dev/null || true)
    [ -n "$IP" ] || { sleep 3; n=$((n + 3)); }
done
[ -n "$IP" ] || { echo "provision-macos-vm.sh: VM never got an IP" >&2; exit 1; }
echo "provision-macos-vm.sh: $VM_NAME at $IP"
echo "$IP" > "$HOME/.bmk-cache/images/.macos_arm64.ip"

# Cirrus Labs base images document a default admin/admin user with SSH
# already enabled (verify this once the VM boots -- not yet confirmed).
# password auth (not a key), so ssh_pw drives it via expect (sshpass isn't
# installed on this host).
SSH_OPTS="-F /dev/null -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"

ssh_pw() {
    # -nocase matters: this VM's prompt is "Password:" (capital P), and a
    # plain-string expect match is case-sensitive -- a lowercase pattern
    # here silently never matches, so the whole call just times out
    # looking like a hung/unreachable VM. Found by connecting manually.
    expect -c "
        set timeout 30
        spawn ssh $SSH_OPTS admin@$IP \"$1\"
        expect {
            -nocase \"password:\" { send \"admin\r\"; exp_continue }
            eof
        }
        catch wait result
        exit [lindex \$result 3]
    "
}

n=0
until ssh_pw 'true' >/dev/null 2>&1 || [ "$n" -ge 90 ]; do
    sleep 5
    n=$((n + 5))
done

# Install this host's public key once, so every later step (including the
# tar-over-ssh transfers build/run-native-macos.sh does) can use plain
# key-based ssh instead of juggling expect + password auth through a pipe.
PUBKEY=$(cat "$HOME/.ssh/id_ed25519.pub" 2>/dev/null || cat "$HOME/.ssh/id_rsa.pub" 2>/dev/null)
[ -n "$PUBKEY" ] || { echo "provision-macos-vm.sh: no local ~/.ssh/id_ed25519.pub or id_rsa.pub found" >&2; exit 1; }
ssh_pw "mkdir -p ~/.ssh && chmod 700 ~/.ssh && grep -qF '$PUBKEY' ~/.ssh/authorized_keys 2>/dev/null || echo '$PUBKEY' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"

# Everything past this point uses plain key-based ssh -- the key just got
# installed above, no more need for ssh_pw/expect.
ssh_key() { ssh $SSH_OPTS "admin@$IP" "$1"; }

echo "provision-macos-vm.sh: installing MacPorts (idempotent)"
ssh_key '
    command -v /opt/local/bin/port >/dev/null 2>&1 && exit 0
    cd /tmp
    curl -fL -o MacPorts.pkg "https://github.com/macports/macports-base/releases/download/v2.12.6/MacPorts-2.12.6-15-Sequoia.pkg"
    sudo installer -pkg MacPorts.pkg -target /
'

echo "provision-macos-vm.sh: installing bmake + gcc + llvm (idempotent; Xcode CLT already provides clang/gcc-the-wrapper, but the gcc leg needs a REAL gcc, not Apple clang aliased to the name)"
ssh_key '
    export PATH=/opt/local/bin:/opt/local/sbin:$PATH
    command -v bmake >/dev/null 2>&1 && command -v gcc14 >/dev/null 2>&1 && exit 0
    sudo port -N install bmake gcc14 llvm-22
    sudo port select --set gcc mp-gcc14
'
echo "provision-macos-vm.sh: $VM_NAME ready at $IP"
