# mk.atfbmk.mk -- builds the ATF Bmake It carries when a test program needs
# it (_ATF_BUNDLED=yes, mk.atf.mk): included by mk.test.mk and mk.tst.mk
# once BUILD_ROOT is known. The libraries are the target;
# scripts/atf-build.sh builds them once per framework build root and says
# what failed, with the compiler's messages, when it cannot.
# @impl 7854-6ae4-9b5d-8fc8
# @impl 7854-6ae4-bac8-49b6

.if !defined(_MK_ATFBMK_MK_) && ${_ATF_BUNDLED:Uno} == "yes"
_MK_ATFBMK_MK_ = 1

${_ATFB_LIBFILES}:
	@env CC='${CC}' CXX='${CXX}' AR='${AR}' TOOLCHAIN='${TOOLCHAIN}' ATF_BMK_MODE='${_ATFB_MODE}' \
		sh ${BMK_MKDIR}/../scripts/atf-build.sh '${_ATFB_DIR}'

.endif
