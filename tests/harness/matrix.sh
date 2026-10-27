#!/bin/sh
# matrix.sh list | run [cell-glob ...] | report
#
# The host x target x toolchain matrix of matrix.tsv, one cell at a time:
#   native cells run the unit suite inside the build platform;
#   cross cells build Hello there for the target and then EXECUTE it on the
#   target platform (a docker container or a VM), recording build and run
#   separately -- a cell that cannot run says why (cross-test-universal-coverage).
# Results go to $BMK_CACHE/results/matrix.tsv; `report` prints the grid.
# VMs a cell needs are brought up on demand and shut down after it (one guest at a time; MATRIX_KEEP_VMS=1 leaves them up).
# A harness process inside a VM never starts another VM: this script runs on
# the host only (vm-nesting-reentrancy-guard-req).
# @impl 0f87-6ad7-1929-a1bb
set -u
HARNESS_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
. "$HARNESS_DIR/lib/env.sh"
MATRIX="$HARNESS_DIR/matrix.tsv"
RES_DIR="$BMK_CACHE/results"; RESULTS="$RES_DIR/matrix.tsv"
LOGS="$BMK_CACHE/logs"; ARTIFACTS="$BMK_CACHE/artifacts"; SYSROOTS="$BMK_CACHE/sysroots"
mkdir -p "$RES_DIR" "$LOGS" "$ARTIFACTS" "$SYSROOTS"
[ -f "$RESULTS" ] || : > "$RESULTS"
VM="sh $HARNESS_DIR/vm.sh"

# One guest at a time: a cell that brought a VM up shuts it down afterwards
# (MATRIX_KEEP_VMS=1 keeps them for interactive use). Several guests plus the
# container VM exhaust a laptop's memory and fill its swap.
KEEP_VMS=${MATRIX_KEEP_VMS:-0}
# reset = shut down AND delete the run overlay, so the next cell boots the
# provisioned layer afresh (harness-vm-layers-req), never a used disk.
vm_release() { [ "$KEEP_VMS" = 1 ] || $VM reset "$1" >/dev/null 2>&1 || true; }
mac_release() { [ "$KEEP_VMS" = 1 ] || tart stop "$(plat "$1" TARTVM)" >/dev/null 2>&1 || true; }

record() { # record <cell> <build> <run> <detail>
    awk -F'\t' -v c="$1" '$1!=c' "$RESULTS" > "$RESULTS.tmp"
    printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$(date '+%Y-%m-%d %H:%M')" >> "$RESULTS.tmp"
    mv "$RESULTS.tmp" "$RESULTS"
}
status_of() { # first word of <log>.status, or MISSING
    if [ -f "$1.status" ]; then cut -d' ' -f1 "$1.status"; else echo MISSING; fi
}
detail_of() { [ -f "$1.status" ] && sed 's/^[A-Z]* *//' "$1.status" | cut -c1-90 || echo ""; }
kind_of() { plat "$1" KIND; }

native_cell() { # native_cell <cell> <build> <toolchain>
    cell=$1 b=$2 tc=$3; log="$LOGS/$cell.log"
    case "$(kind_of "$b")" in
        # A host without docker, or one that cannot accelerate a guest that
        # needs it (an amd64 BSD on Apple silicon), blocks the cell with the
        # reason; a guest that fails to come up says why (vm.sh's message).
        docker) command -v docker >/dev/null 2>&1 || { record "$cell" "-" "blocked" "docker is not installed on this host"; return; }
                sh "$HARNESS_DIR/build/run-native-docker.sh" "$(plat "$b" IMAGE)" "$(plat "$b" PLATFORM)" "$tc" "$log" >/dev/null 2>&1 ;;
        vm)     why=$($VM status "$b" 2>/dev/null | sed -n 's/.*BLOCKED[^:]*: //p')
                [ -z "$why" ] || { record "$cell" "-" "blocked" "$why"; return; }
                $VM up "$b" >"$log.up" 2>&1 || { record "$cell" "-" "fail" "vm.sh up $b: $(tail -1 "$log.up" | cut -c1-120)"; return; }
                sh "$HARNESS_DIR/build/run-native-vm.sh" "$b" "$(plat "$b" SSH_PORT)" "$tc" "$(plat "$b" BMAKE)" "$log" >/dev/null 2>&1
                vm_release "$b" ;;
        vm-host) sh "$HARNESS_DIR/build/run-native-macos.sh" "$tc" "$log" >/dev/null 2>&1
                mac_release "$b" ;;
        # harness-windows-host-cells-req: the platform is this machine itself
        # @impl 7854-6adf-8cd3-e408
        host)   sh "$HARNESS_DIR/build/run-native-host.sh" "$b" "$tc" "$log" >/dev/null 2>&1 ;;
        *)      record "$cell" "-" "blocked" "no runner for $b yet"; return ;;
    esac
    s=$(status_of "$log")
    if [ "$s" = BLOCKED ]; then record "$cell" "-" "blocked" "$(detail_of "$log")"; return; fi
    r=fail; [ "$s" = PASS ] && r=pass
    record "$cell" "$r" "-" "$(detail_of "$log")"
}

ensure_sysroot() { # ensure_sysroot <os-arch>  -> prints the tar path
    # returns 0 = path printed, 1 = the recipe failed, 2 = no recipe (a harness gap)
    t=$1; tar="$SYSROOTS/$t.tar"; os=${t%%-*}; arch=${t#*-}
    [ -f "$tar" ] && { echo "$tar"; return 0; }
    case "$t" in
        linux-*)   sh "$HARNESS_DIR/fetch/build-sysroot-linux.sh" "$arch" "$tar" >&2 || return 1 ;;
        freebsd-arm64|netbsd-arm64) $VM up "${os}_arm64" >&2 && $VM sysroot "${os}_arm64" "$tar" >&2 || return 1; vm_release "${os}_arm64" ;;
        freebsd-amd64) sh "$HARNESS_DIR/fetch/build-sysroot-freebsd.sh" "$tar" amd64 15.1-RELEASE >&2 || return 1 ;;
        netbsd-amd64)  sh "$HARNESS_DIR/fetch/build-sysroot-netbsd.sh" amd64 "$tar" 11.0 >&2 || return 1 ;;
        macos-arm64)   sh "$HARNESS_DIR/fetch/build-sysroot-macos.sh" "$tar" >&2 || return 1 ;;
        *) return 2 ;;
    esac
    [ -f "$tar" ] && echo "$tar"
}

cross_cell() { # cross_cell <cell> <build> <target> <exec>
    cell=$1 b=$2 t=$3 e=$4; os=${t%%-*}; arch=${t#*-}
    blog="$LOGS/$cell.build.log"; xlog="$LOGS/$cell.exec.log"; out="$ARTIFACTS/$cell"
    rc=0; sysroot=$(ensure_sysroot "$t") || rc=$?
    case "$rc" in
        0) ;;
        2) record "$cell" "gap" "-" "harness has no sysroot recipe for $t yet"; return ;;
        *) record "$cell" "fail" "-" "building the $t sysroot failed (see $LOGS)"; return ;;
    esac
    case "$(kind_of "$b")" in
        docker) sh "$HARNESS_DIR/build/build-cross-docker.sh" "$(plat "$b" IMAGE)" "$(plat "$b" PLATFORM)" "$os" "$arch" "$sysroot" "$out" "$blog" >/dev/null 2>&1 ;;
        vm)     $VM up "$b" >/dev/null 2>&1
                sh "$HARNESS_DIR/build/build-cross-vm.sh" "$b" "$(plat "$b" SSH_PORT)" "$os" "$arch" "$sysroot" "$out" "$blog" >/dev/null 2>&1
                vm_release "$b" ;;
        *)      record "$cell" "-" "-" "no cross builder for $b"; return ;;
    esac
    bs=$(status_of "$blog")
    if [ "$bs" != PASS ]; then
        why=$(grep -m1 -E 'ld64.lld: error|: error:|fatal error|^error' "$blog" 2>/dev/null | cut -c1-110)
        record "$cell" "fail" "-" "${why:-$(detail_of "$blog")}"; return
    fi
    case "$e" in
        blocked:*) record "$cell" "pass" "blocked" "${e#blocked:}"; return ;;
        none:*)    record "$cell" "pass" "n/a" "${e#none:}"; return ;;
    esac
    case "$(kind_of "$e")" in
        docker) sh "$HARNESS_DIR/test/exec-cross-docker.sh" "$out/Hello" "$t" "$(plat "$e" PLATFORM)" "$xlog" >/dev/null 2>&1 ;;
        vm)     $VM up "$e" >/dev/null 2>&1 || { record "$cell" "pass" "fail" "vm.sh up $e failed"; return; }
                sh "$HARNESS_DIR/test/exec-cross-vm.sh" "$out/Hello" "$t" "$e" "$xlog" >/dev/null 2>&1
                vm_release "$e" ;;
        *)      record "$cell" "pass" "blocked" "no executor for $e"; return ;;
    esac
    xs=$(status_of "$xlog"); r=fail; [ "$xs" = PASS ] && r=pass
    record "$cell" "pass" "$r" "$(detail_of "$xlog")"
}

run_cell() { # run_cell <line fields...>
    cell=$1 kind=$2 b=$3 t=$4 tc=$5 e=$6
    printf '== %s\n' "$cell"
    case "$kind" in
        native) case "$e" in blocked:*) record "$cell" "-" "blocked" "${e#blocked:}"; return ;; esac
                native_cell "$cell" "$b" "$tc" ;;
        cross)  cross_cell "$cell" "$b" "$t" "$e" ;;
    esac
    grep "^$cell	" "$RESULTS" | cut -f2-4 | sed 's/^/   /'
}

cells() { awk -F'\t' '!/^#/ && NF>=6' "$MATRIX"; }

cmd=${1:-}; [ $# -gt 0 ] && shift
case "$cmd" in
    list)  printf '%-34s %-7s %-17s %-14s %-6s %s\n' cell kind build target tc exec
           cells | awk -F'\t' '{printf "%-34s %-7s %-17s %-14s %-6s %s\n",$1,$2,$3,$4,$5,$6}' ;;
    run)   cells | while IFS='	' read -r c k b t tc e; do
               ok=no; if [ $# -eq 0 ]; then ok=yes; else for g in "$@"; do case "$c" in $g) ok=yes ;; esac; done; fi
               [ "$ok" = yes ] && run_cell "$c" "$k" "$b" "$t" "$tc" "$e" </dev/null
           done ;;
    report) printf '%-34s %-8s %-8s %s\n' cell build run detail
           cells | while IFS='	' read -r c k b t tc e; do
               r=$(grep "^$c	" "$RESULTS" | head -1)
               if [ -n "$r" ]; then printf '%s\n' "$r" | awk -F'\t' '{printf "%-34s %-8s %-8s %s\n",$1,$2,$3,$4}'
               else case "$e" in blocked:*|none:*) printf '%-34s %-8s %-8s %s\n' "$c" "-" "${e%%:*}" "${e#*:}" ;;
                    *) printf '%-34s %-8s %-8s\n' "$c" "-" "not run" ;; esac; fi
           done ;;
    *) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
