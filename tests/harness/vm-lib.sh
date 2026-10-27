#!/bin/sh
# @impl 0f87-6ad7-1929-a1bb
# vm-lib.sh — shared QEMU boot/ssh-wait helpers for the VM-hosted platforms.
# Not directly executable; sourced by provision/provision-vm.sh and friends.
#
# Factors out the pattern proven this session for the NetBSD-arm64 VM
# (UEFI + hvf) and the FreeBSD-amd64 VM (BIOS + TCG): boot headless with a
# forwarded ssh port, poll until ssh answers, then drive setup over ssh --
# no serial-console keystroke automation needed for either, since both
# platforms' official images come with sshd enabled and either an existing
# unlocked root account (FreeBSD's plain VM-IMAGE) or one this session
# already provisioned with an authorized_keys entry (NetBSD).

# Guests trust the harness key ($HARNESS_KEY, set by vm.sh); older callers
# that set nothing keep ssh's default identities.
_vm_ssh_opts() {
    printf '%s' "-F /dev/null -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
    _k=${HARNESS_KEY:-${BMK_CACHE:-$HOME/.bmk-cache}/keys/harness_ed25519}
    [ -f "$_k" ] && printf ' %s' "-i $_k -o IdentitiesOnly=yes"
    return 0
}

vm_wait_ssh() {
    # vm_wait_ssh <port> <timeout-seconds>
    port="${1:?}"
    timeout="${2:-180}"
    waited=0
    while [ "$waited" -lt "$timeout" ]; do
        if ssh $(_vm_ssh_opts) -o ConnectTimeout=3 -o BatchMode=yes -p "$port" root@localhost 'true' >/dev/null 2>&1; then
            return 0
        fi
        sleep 3
        waited=$((waited + 3))
    done
    echo "vm_wait_ssh: no ssh response on port $port after ${timeout}s" >&2
    return 1
}

vm_ssh() {
    # vm_ssh <port> <command...>
    port="${1:?}"; shift
    ssh $(_vm_ssh_opts) -o ConnectTimeout=5 -p "$port" root@localhost "$@"
}

vm_scp_in() {
    # vm_scp_in <port> <local-tar-stdin-source> <remote-dir>
    # Streams a tar of the given local path into remote-dir via ssh (avoids
    # needing scp/sftp subsystem configured, matches the pattern already
    # proven for the NetBSD VM this session). COPYFILE_DISABLE + --no-xattrs
    # avoids AppleDouble ._foo sidecars (macOS quarantine/provenance xattrs)
    # turning into literal ._foo files on the far end that a naive SRCS!=
    # glob then picks up as real source -- found empirically this session.
    port="${1:?}"; local_path="${2:?}"; remote_dir="${3:?}"
    (
        export COPYFILE_DISABLE=1
        tar --no-xattrs --no-acls --no-mac-metadata -C "$(dirname "$local_path")" -cf - "$(basename "$local_path")" 2>/dev/null \
            || tar -C "$(dirname "$local_path")" -cf - "$(basename "$local_path")"
    ) | vm_ssh "$port" "rm -rf '$remote_dir' && mkdir -p '$remote_dir' && tar -C '$remote_dir' -xf -"
}

vm_shutdown() {
    # vm_shutdown <port> <qemu-pid>
    # Always shut down a VM this way, never a bare `kill` on the qemu
    # process -- found empirically this session: repeated hard kills (no
    # guest-side graceful shutdown) corrupted the NetBSD-arm64 VM's root
    # filesystem badly enough to abort automatic fsck on the next boot and
    # (separately) lose its sshd host keys, which is what actually caused
    # this session's "flaky SSH" symptoms for that VM, not a networking or
    # auth issue. Tries a real guest-side shutdown over ssh first (works on
    # both BSDs); only falls back to killing the process if ssh is already
    # unreachable, since at that point there's nothing gracefully
    # shuttable anyway.
    # Returns 1 when QEMU had to be killed: its disk image may then have lost
    # writes still in QEMU's own metadata cache (a NetBSD layer saved so had
    # a broken root filesystem, 2026-10-27) -- a caller saving a disk must
    # not keep it.
    port="${1:?}"; pid="${2:?}"
    # (/sbin explicitly: NetBSD's root has none on PATH over a non-interactive
    # ssh session -- shutdown was "not found" and every NetBSD guest was
    # killed instead, 2026-10-27)
    _sd_out=$(vm_ssh "$port" 'PATH=$PATH:/sbin:/usr/sbin; export PATH; sync; sync; shutdown -p now || poweroff' 2>&1) || true
    n=0
    while kill -0 "$pid" 2>/dev/null && [ "$n" -lt 120 ]; do
        sleep 2
        n=$((n + 2))
    done
    if kill -0 "$pid" 2>/dev/null; then
        echo "vm_shutdown: the guest did not power off within 120 s; QEMU killed${_sd_out:+ (the shutdown command over ssh said: $_sd_out)}" >&2
        kill "$pid" 2>/dev/null || true
        return 1
    fi
    return 0
}
