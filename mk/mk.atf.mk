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

.if !defined(_MK_ATF_MK_)
_MK_ATF_MK_ = 1

KYUA ?= kyua
_ATF_KYUA_BIN != command -v ${KYUA} 2>/dev/null || true
.if !empty(_ATF_KYUA_BIN)
_ATF_PC_ENV = env PKG_CONFIG_PATH=${_ATF_KYUA_BIN:H:H}/lib/pkgconfig$${PKG_CONFIG_PATH:+:$$PKG_CONFIG_PATH}
.else
_ATF_PC_ENV =
.endif

.endif # _MK_ATF_MK_
