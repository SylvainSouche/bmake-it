# Makefile — orchestrates the Bmake It platform test matrix.
#
# Plain make (GNU or BSD, doesn't matter which), deliberately NOT Bmake It
# itself -- this drives the tests, it is not the thing being tested.
#
# Phases, each cacheable and independently re-runnable:
#   fetch     download/build images and sysroots (file-based caching under
#             $(CACHE) -- re-running skips anything already present)
#   provision build tagged Docker images / boot+package VMs once
#   build     Step A: native build+test under every toolchain, plus every
#             cross-compile direction, for every implemented platform
#   test      Step B: execute every cross-built artifact against its real
#             target (native suite execution already happened in `build`,
#             as part of run-tests.sh)
#   report    collect build/ and test/ logs into one result set
#
# See platforms.mk for the platform table (implemented + pending rows) and
# /Users/sylvain/.claude/plans/composed-imagining-whistle.md for the design.
#
# STATUS: Docker-hosted platforms (linux_amd64_emu, linux_arm64,
# linux_amd64_musl) are fully implemented. VM-hosted platforms (macos_arm64,
# linux_amd64_vm, freebsd_amd64, netbsd_amd64, netbsd_arm64) are scaffolded
# in platforms.mk but their fetch/provision/build steps are not yet wired up
# -- `make fetch`/`make provision`/`make build` say so explicitly rather
# than silently skipping them.

SHELL := /bin/sh
HARNESS_DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
BMK_ROOT := $(abspath $(HARNESS_DIR)/../..)
CACHE := $(HOME)/.bmk-cache
IMAGES := $(CACHE)/images
SYSROOTS := $(CACHE)/sysroots
LOGS := $(CACHE)/logs
ARTIFACTS := $(CACHE)/artifacts
RESULTS := $(CACHE)/results.txt

include platforms.mk

.PHONY: all fetch provision build test report clean-cache help

all: report

help:
	@echo "tests/harness Makefile -- plain make, not Bmake It"
	@echo "targets: fetch  provision  build  test  report  all  clean-cache"
	@echo "platforms.mk: $(PLATFORMS)"
	@echo "(VM-hosted platforms are not yet wired up -- see STATUS comment at top of this file)"

# ---------------------------------------------------------------------------
# Phase 1: fetch -- sysroots (VM images: not yet implemented, see STATUS)
# ---------------------------------------------------------------------------
$(SYSROOTS)/linux-amd64.tar:
	@mkdir -p $(SYSROOTS)
	fetch/build-sysroot-linux.sh amd64 $@

$(SYSROOTS)/linux-arm64.tar:
	@mkdir -p $(SYSROOTS)
	fetch/build-sysroot-linux.sh arm64 $@

$(SYSROOTS)/netbsd-arm64.tar:
	@mkdir -p $(SYSROOTS)
	fetch/build-sysroot-netbsd.sh evbarm-aarch64 $@

$(IMAGES)/netbsd-arm64.img:
	@mkdir -p $(IMAGES)
	fetch/fetch-image.sh netbsd_arm64 $@

fetch: $(SYSROOTS)/linux-amd64.tar $(SYSROOTS)/linux-arm64.tar $(SYSROOTS)/netbsd-arm64.tar $(IMAGES)/netbsd-arm64.img
	@echo "fetch: macos_arm64 uses 'tart pull' (see provision-macos-vm.sh), not a Makefile"
	@echo "       target -- run it manually once if you haven't: tart pull ghcr.io/cirruslabs/macos-sequoia-base:latest"
	@echo "       linux_amd64_vm not yet implemented; freebsd_amd64/netbsd_amd64 frozen (see STATUS)."

# ---------------------------------------------------------------------------
# Phase 2: provision -- Docker images built+tagged once (VM provisioning:
# not yet implemented, see STATUS)
# ---------------------------------------------------------------------------
GLIBC_INSTALL := apt-get update -qq && apt-get install -y -qq --no-install-recommends bmake clang lld gcc file
MUSL_INSTALL := apk add --no-cache bmake clang lld gcc musl-dev file

$(IMAGES)/.linux-glibc-amd64.provisioned:
	@mkdir -p $(IMAGES)
	provision/provision-docker.sh debian:bookworm-slim linux/amd64 "$(GLIBC_INSTALL)" bmk/linux-glibc:amd64
	@touch $@

$(IMAGES)/.linux-glibc-arm64.provisioned:
	@mkdir -p $(IMAGES)
	provision/provision-docker.sh debian:bookworm-slim linux/arm64 "$(GLIBC_INSTALL)" bmk/linux-glibc:arm64
	@touch $@

$(IMAGES)/.linux-musl-amd64.provisioned:
	@mkdir -p $(IMAGES)
	provision/provision-docker.sh alpine:latest linux/amd64 "$(MUSL_INSTALL)" bmk/linux-musl:amd64
	@touch $@

$(IMAGES)/.netbsd_arm64.provisioned: $(IMAGES)/netbsd-arm64.img
	provision/provision-vm.sh netbsd_arm64 $(IMAGES)/netbsd-arm64.img 2222
	@touch $@

$(IMAGES)/.macos_arm64.provisioned:
	provision/provision-macos-vm.sh
	@touch $@

provision: fetch \
	$(IMAGES)/.linux-glibc-amd64.provisioned \
	$(IMAGES)/.linux-glibc-arm64.provisioned \
	$(IMAGES)/.linux-musl-amd64.provisioned
	-$(MAKE) $(IMAGES)/.netbsd_arm64.provisioned
	-$(MAKE) $(IMAGES)/.macos_arm64.provisioned
	@echo "provision: freebsd_amd64/netbsd_amd64 frozen (QEMU/TCG boot stall);"
	@echo "           linux_amd64_vm not yet implemented -- see provision/ and the plan."

# ---------------------------------------------------------------------------
# Phase 3 (Step A): build -- native (both toolchains) + all cross builds
# ---------------------------------------------------------------------------
build: provision
	@mkdir -p $(LOGS) $(ARTIFACTS)
	@echo "=== Step A: native builds (Docker platforms) ==="
	-build/run-native-docker.sh bmk/linux-glibc:amd64 linux/amd64 llvm $(LOGS)/native-linux_amd64_emu-llvm.log
	-build/run-native-docker.sh bmk/linux-glibc:amd64 linux/amd64 gcc  $(LOGS)/native-linux_amd64_emu-gcc.log
	-build/run-native-docker.sh bmk/linux-glibc:arm64 ""          llvm $(LOGS)/native-linux_arm64-llvm.log
	-build/run-native-docker.sh bmk/linux-glibc:arm64 ""          gcc  $(LOGS)/native-linux_arm64-gcc.log
	-build/run-native-docker.sh bmk/linux-musl:amd64  linux/amd64 llvm $(LOGS)/native-linux_amd64_musl-llvm.log
	-build/run-native-docker.sh bmk/linux-musl:amd64  linux/amd64 gcc  $(LOGS)/native-linux_amd64_musl-gcc.log
	@echo "=== Step A: native builds (VM platforms, best-effort) ==="
	-build/run-native-vm.sh netbsd_arm64 2222 llvm /usr/bin/make $(LOGS)/native-netbsd_arm64-llvm.log
	-build/run-native-vm.sh netbsd_arm64 2222 gcc  /usr/bin/make $(LOGS)/native-netbsd_arm64-gcc.log
	-build/run-native-macos.sh llvm $(LOGS)/native-macos_arm64-llvm.log
	-build/run-native-macos.sh gcc  $(LOGS)/native-macos_arm64-gcc.log
	@echo "=== Step A: cross builds (llvm only -- gcc has no per-target cross compiler) ==="
	-build/build-cross-docker.sh bmk/linux-glibc:arm64 "" linux amd64 \
		$(SYSROOTS)/linux-amd64.tar $(ARTIFACTS)/arm64-to-amd64 $(LOGS)/cross-arm64_to_amd64.log
	-build/build-cross-docker.sh bmk/linux-glibc:amd64 linux/amd64 linux arm64 \
		$(SYSROOTS)/linux-arm64.tar $(ARTIFACTS)/amd64-to-arm64 $(LOGS)/cross-amd64_to_arm64.log
	-build/build-cross-docker.sh bmk/linux-glibc:arm64 "" netbsd aarch64 \
		$(SYSROOTS)/netbsd-arm64.tar $(ARTIFACTS)/linux_arm64-to-netbsd_arm64 $(LOGS)/cross-linux_arm64_to_netbsd_arm64.log
	@echo "build: VM-hosted native+cross builds not yet implemented (macos, linux_amd64_vm, freebsd, netbsd)"

# ---------------------------------------------------------------------------
# Phase 4 (Step B): test -- execute every cross artifact built in Step A
# ---------------------------------------------------------------------------
test: build
	@echo "=== Step B: execute cross artifacts ==="
	-test/exec-cross-docker.sh $(ARTIFACTS)/arm64-to-amd64/Hello linux-amd64 linux/amd64 $(LOGS)/exec-arm64_to_amd64.log
	-test/exec-cross-docker.sh $(ARTIFACTS)/amd64-to-arm64/Hello linux-arm64 ""          $(LOGS)/exec-amd64_to_arm64.log

# ---------------------------------------------------------------------------
# Phase 5: report
# ---------------------------------------------------------------------------
report: test
	report/collect.sh $(LOGS) $(RESULTS)
	@echo
	@cat $(RESULTS)

clean-cache:
	rm -rf $(CACHE)
