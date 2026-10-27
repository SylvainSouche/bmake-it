# packages-netbsd.sh install <dir> | host-fetch <dir> <arch> <release>
# (guest-packages-from-cache-req). The base system has cc, gcc, make and
# atf; the suite also needs these, from pkgsrc binaries.
#   host-fetch <dir> <arch> <release>   run on the HOST by vm.sh: resolve the
#       packages and their dependencies from the repository's pkg_summary and
#       download them into <dir> -- the guest's own downloads drop under
#       QEMU/WHPX (obs netbsd-amd64-whpx-downloads-drop-obs)
#   install <dir>   run in the guest: install them from <dir>, no network
set -e
PKGS="pkgconf cmake doxygen atf kyua clang lld"
mode=${1:?install or host-fetch}; dir=${2:?directory}
case "$mode" in
    host-fetch)
        arch=${3:?arch}; rel=${4:?release}
        url="https://cdn.NetBSD.org/pub/pkgsrc/packages/NetBSD/$arch/$rel/All"
        mkdir -p "$dir"
        curl -fsSL --retry 5 -o "$dir/pkg_summary.gz" "$url/pkg_summary.gz"
        gzip -dc "$dir/pkg_summary.gz" | python3 -c '
import sys, re
want = sys.argv[1].split()
pkgs, cur = {}, {}
for line in sys.stdin:
    line = line.rstrip("\n")
    if not line:
        if "PKGNAME" in cur: pkgs[cur["PKGNAME"]] = cur.get("DEPENDS", [])
        cur = {}; continue
    k, _, v = line.partition("=")
    if k == "DEPENDS": cur.setdefault("DEPENDS", []).append(v)
    elif k == "PKGNAME": cur["PKGNAME"] = v
if "PKGNAME" in cur: pkgs[cur["PKGNAME"]] = cur.get("DEPENDS", [])
byname = {}  # a name may come in several versions: the highest, as pkg_add picks
def ver(p): return [int(x) for x in re.findall(r"[0-9]+", p.rsplit("-", 1)[1])]
for p in pkgs:
    b = re.sub(r"-[0-9][^-]*$", "", p)
    if b not in byname or ver(p) > ver(byname[b]): byname[b] = p
def names(pat):  # the package names a dependency pattern may mean
    m = re.match(r"\{([^}]*)\}(.*)", pat)
    alts = [a + m.group(2) for a in m.group(1).split(",")] if m else [pat]
    return [re.split(r"[<>=]|-\[|-[0-9]", a)[0] for a in alts]
todo, done = list(want), set()
while todo:
    n = todo.pop()
    p = next((byname[c] for c in names(n) if c in byname), None)
    if p is None: sys.exit("no package in pkg_summary for: " + n)
    if p in done: continue
    done.add(p); todo += pkgs[p]
print("\n".join(sorted(done)))
' "$PKGS" > "$dir/.closure"
        while read -r p; do
            [ -f "$dir/$p.tgz" ] || curl -fsSL --retry 5 -o "$dir/$p.tgz" "$url/$p.tgz"
        done < "$dir/.closure"
        rm -f "$dir/.closure" ;;
    install)
        PATH=$PATH:/usr/sbin:/usr/pkg/sbin:/usr/pkg/bin; export PATH
        PKG_PATH=$dir; export PKG_PATH
        pkg_add -v $PKGS ;;
esac
