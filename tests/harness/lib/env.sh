#!/bin/sh
# env.sh -- where the harness keeps things. Sourced, never executed.
#
#   BMK_CACHE   downloaded originals, decompressed bases, provisioned layers,
#               VM run overlays, keys, logs. Large; may live on an external
#               drive (exFAT is fine -- it holds no sockets or symlinks).
#               Default: $HOME/.bmk-cache
#   BMK_DISKS   the guests' read-heavy disk files: base/ and layers/. A cold
#               boot does thousands of small random reads, which an external
#               USB drive serves badly: keep these on a fast local disk when
#               BMK_CACHE is on one (about 4 GB per BSD guest).
#               Default: $BMK_CACHE
#   BMK_VMS     the throw-away run overlays (write-heavy, recreated by `vm.sh
#               reset`): put them on a fast local disk when BMK_CACHE is on a
#               slow external one. Default: $BMK_CACHE/vms
#   BMK_RUN     unix sockets and pidfiles of running VMs. Must be a local
#               filesystem that supports sockets (not exFAT).
#               Default: ${TMPDIR:-/tmp}/bmk-vm
#
# Layout under BMK_CACHE (a platform id is e.g. freebsd_arm64):
#   images/<file>            as published, verified, never modified
#   base/<id>.<fmt>          decompressed image, read-only, never booted directly (BMK_DISKS)
#   layers/<id>.qcow2        base + provisioning (ssh key, sshd, packages)   (BMK_DISKS)
#   vms/<id>/                a run (under BMK_VMS): disk.qcow2 overlay on the layer, UEFI vars
#   keys/harness_ed25519     the key the guests trust
#   logs/ artifacts/ sysroots/
# @impl 0f87-6ad7-1929-a1bb
BMK_CACHE=${BMK_CACHE:-$HOME/.bmk-cache}
BMK_RUN=${BMK_RUN:-${TMPDIR:-/tmp}/bmk-vm}
BMK_RUN=${BMK_RUN%/}
BMK_DISKS=${BMK_DISKS:-$BMK_CACHE}
BMK_VMS=${BMK_VMS:-$BMK_DISKS/vms}
export BMK_CACHE BMK_RUN BMK_VMS BMK_DISKS
HARNESS_DIR=${HARNESS_DIR:-$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)}

# plat <id> <field>: a field of platforms.mk (the single source of truth).
plat() {
    printf 'include %s/platforms.mk\n_x:\n\t@echo \"$(%s_%s)\"\n' "$HARNESS_DIR" "$2" "$1" \
        | make -s -f - _x 2>/dev/null
}
