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
#
# atf-runtime-only-is-named-req: when neither works but the library's
# run-time file is there (lib<it>.so.N), the answer is runtime=<file>: only
# the run-time part is installed, not what building against it needs
# (headers, .pc, lib<it>.so) -- FreeBSD's base package FreeBSD-atf instead
# of the atf package, Debian's libatf-c++-2 without libatf-dev (FreeBSD,
# 2026-10-29: "FreeBSD-atf was installed not atf itself").
# @impl 7854-6ae3-3af3-93db
_ATF_FOUND_CMD = { ${_ATF_PC_ENV} pkg-config --exists $$1 2>/dev/null && echo pc; } || \
	{ _o=$${TMPDIR:-/tmp}/bmk-atf-probe.$$$$; echo 'int main(void){return 0;}' | $$2 -x $$3 - -l$$1 -o "$$_o" >/dev/null 2>&1 && echo lib; rm -f "$$_o" "$$_o.exe"; } | grep . || \
	{ _rt=$$(ls /usr/lib/lib$$1.so.* /usr/lib/*/lib$$1.so.* /usr/local/lib/lib$$1.so.* /usr/pkg/lib/lib$$1.so.* 2>/dev/null | head -1); \
	  if [ -n "$$_rt" ]; then echo "runtime=$$_rt"; else echo no; fi; }
_ATF_INSTALL = Install ATF (FreeBSD: pkg install atf; NetBSD: pkg_add atf; Debian: apt install libatf-dev; MacPorts: port install atf) -- or build with BMK_ATF=bundled to use the ATF Bmake It carries
_ATF_NOT_FOUND = not found -- pkg-config finds no .pc for it (searched its default path and ${_ATF_PC_DIRS:O:u}), and -l<it> does not link either. ${_ATF_INSTALL}, or add the directory holding its .pc file to PKG_CONFIG_PATH
# (@RT@: the run-time file found; callers substitute it)
_ATF_RUNTIME_ONLY = is only installed as a run-time library (@RT@), without the headers and .pc file a test program is built with -- on FreeBSD that is the base system's FreeBSD-atf package, not the atf package. ${_ATF_INSTALL}

# The ATF Bmake It carries: ATF's own sources (contrib/atf-0.23) with
# contrib/atf-bmk, built with the module's compilers once per framework
# build root (mk.atfbmk.mk, scripts/atf-build.sh). _ATF_BUNDLED=yes selects
# it, in one of two modes:
#   win    native-windows-tests-req (atf-for-windows-dec): a native Windows
#          runtime (TOOLCHAIN=msvc, ABI=mingw) on a Cygwin host has no ATF
#          to find -- always this one, with the Windows layer; the Cygwin
#          Kyua runs the test programs
#   posix  bundled-atf-selectable-req: BMK_ATF=bundled on any other target,
#          instead of the installed ATF -- the same tests against that
#          version (the installed Kyua runs them)
# The flags are lazy: BUILD_ROOT is not known yet where mk.tst.mk includes
# this file.
# @impl 7854-6ae4-9b5d-8fc8
# @impl 7854-6ae4-bac8-49b6
BMK_ATF ?=
.if !empty(BMK_ATF) && "${BMK_ATF}" != "bundled" && "${BMK_ATF}" != "installed"
.  error "BMK_ATF=${BMK_ATF}: expected bundled (the ATF Bmake It carries, built from contrib/) or installed (the default: the system's ATF)"
.endif
_ATF_BUNDLED = no
_ATFB_MODE =
.if !empty(.MAKE.OS:U:tl:Mcygwin*) && ${TARGET:Uwin} == "win" && (${TOOLCHAIN:U} == "msvc" || ${ABI:U} == "mingw")
_ATF_BUNDLED = yes
_ATFB_MODE = win
.elif "${BMK_ATF}" == "bundled"
_ATF_BUNDLED = yes
_ATFB_MODE = posix
.endif
.if ${_ATF_BUNDLED} == "yes"
_ATFB_DIR = ${.CURDIR}/../${BUILD_ROOT}/atf
_ATFB_CXXRT =
# (scripts/atf-build.sh stages the public headers into ${_ATFB_DIR}/include,
# as an install would -- with MSVC's missing unistd.h)
_ATFB_CFLAGS = -I${_ATFB_DIR}/include
.  if ${TOOLCHAIN:U} == "msvc"
_ATFB_LIBFILES = ${_ATFB_DIR}/atf-c.lib ${_ATFB_DIR}/atf-c++.lib
.  else
_ATFB_LIBFILES = ${_ATFB_DIR}/libatf-c.a ${_ATFB_DIR}/libatf-c++.a
.    if ${_ATFB_MODE} == "win"
# libatf-c's regex is C++ there (std::regex): a C test program links the
# C++ runtime the compiler driver would (libstdc++ or libc++; cl.exe does
# it by itself).
_ATFB_CXXRT_CMD = echo 'int main(){return 0;}' | ${CXX} -x c++ - -o /dev/null -\#\#\# 2>&1 | grep -o '"-lc++"\|"-lstdc++"' | head -1 | tr -d '"'
_ATFB_CXXRT = ${_ATFB_CXXRT_CMD:sh}
.    endif
.  endif
_ATFB_C_LIBS = -L${_ATFB_DIR} -latf-c ${_ATFB_CXXRT}
_ATFB_CXX_LIBS = -L${_ATFB_DIR} -latf-c++ -latf-c
.endif

.endif # _MK_ATF_MK_
