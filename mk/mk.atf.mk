# mk.atf.mk — where ATF is found: included by mk.test.mk and mk.tst.mk
# before they ask pkg-config for atf-c / atf-c++.
#
# atf-from-kyua-prefix-req: ATF is looked up in the prefix of the Kyua that
# runs the tests too (<prefix>/lib/pkgconfig, before the default path) --
# they are installed side by side (MacPorts, pkgsrc, a source build in
# /usr/local), and a pkg-config whose default path lacks that prefix
# (Cygwin's: no /usr/local) otherwise found no atf-c and fell back to a bare
# -latf-c with no -I or -L (2026-10-28). _ATF_PC_ENV prefixes those
# pkg-config calls.
# @impl 7854-6ae2-336d-ccde
#
# FreeBSD keeps .pc files in libdata/pkgconfig, and its Kyua is in the base
# system (/usr/bin) while the atf package is under /usr/local: both layouts
# are searched, beside Kyua and under /usr/local (2026-10-29).

.if !defined(_MK_ATF_MK_)
_MK_ATF_MK_ = 1

KYUA ?= kyua
_ATF_KYUA_BIN != command -v ${KYUA} 2>/dev/null || true
_ATF_PC_DIRS  = ${_ATF_KYUA_BIN:H:H:S|$|/lib/pkgconfig|} ${_ATF_KYUA_BIN:H:H:S|$|/libdata/pkgconfig|}
_ATF_PC_DIRS += /usr/local/lib/pkgconfig /usr/local/libdata/pkgconfig
_ATF_PC_ENV   = env PKG_CONFIG_PATH=${_ATF_PC_DIRS:O:u:ts:}$${PKG_CONFIG_PATH:+:$$PKG_CONFIG_PATH}

# atf-not-found-is-explained-req: _atf_found <lib> answers pc (pkg-config
# knows it), lib (no .pc, but -l<lib> links) or no. A test module stops on
# "no" with what was looked for, instead of handing the linker a bare
# -latf-c++ it cannot resolve ("unable to find library -latf-c++", FreeBSD,
# 2026-10-29).
# @impl 7854-6ae3-2698-aa85
_ATF_FOUND_CMD = { ${_ATF_PC_ENV} pkg-config --exists $$1 2>/dev/null && echo pc; } || \
	{ _o=$${TMPDIR:-/tmp}/bmk-atf-probe.$$$$; echo 'int main(void){return 0;}' | $$2 -x $$3 - -l$$1 -o "$$_o" >/dev/null 2>&1 && echo lib; rm -f "$$_o" "$$_o.exe"; } | grep . || echo no
_ATF_NOT_FOUND = not found -- pkg-config finds no .pc for it (searched its default path and ${_ATF_PC_DIRS:O:u}), and -l<it> does not link either. Install ATF (FreeBSD: pkg install atf; NetBSD: pkg_add atf; Debian: apt install libatf-dev; MacPorts: port install atf), or add the directory holding its .pc file to PKG_CONFIG_PATH

.endif # _MK_ATF_MK_
