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
# linux_amd64_musl) and the arm64 BSD VMs (freebsd_arm64, netbsd_arm64, run
# hardware-accelerated by vm.sh) are implemented: native suites and cross
# builds that are then EXECUTED on the target, driven by matrix.tsv/matrix.sh.
# Not wired up: macos_arm64 as a build host for cross cells, linux_amd64_vm;
# frozen: freebsd_amd64/netbsd_amd64 (QEMU/TCG boot stall on an arm64 host);
# no Windows guest yet. matrix.sh lists every such cell with its reason.

SHELL := /bin/sh
HARNESS_DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
BMK_ROOT := $(abspath $(HARNESS_DIR)/../..)
# Where everything lives: BMK_CACHE (default ~/.bmk-cache), see lib/env.sh.
BMK_CACHE ?= $(HOME)/.bmk-cache
export BMK_CACHE
CACHE := $(BMK_CACHE)
# the guests' read-heavy disk files (see lib/env.sh); default: in the cache
BMK_DISKS ?= $(BMK_CACHE)
export BMK_DISKS
DISKS := $(BMK_DISKS)
IMAGES := $(CACHE)/images
SYSROOTS := $(CACHE)/sysroots
LOGS := $(CACHE)/logs
ARTIFACTS := $(CACHE)/artifacts
RESULTS := $(CACHE)/results.txt

include platforms.mk

.PHONY: all fetch provision build test report clean-cache help vm-status

all: report

help:
	@echo "tests/harness Makefile -- plain make, not Bmake It"
	@echo "targets: fetch  provision  build  test  report  all  clean-cache  vm-status"
	@echo "  build = the native suites of matrix.tsv, test = the cross cells (built, then run on the target)"
	@echo "  report = the grid; one cell: sh matrix.sh run <cell>; VMs: sh vm.sh status"
	@echo "cache: $(CACHE)   (override: make BMK_CACHE=/path)"
	@echo "platforms.mk: $(PLATFORMS)"

# ---------------------------------------------------------------------------
# Phase 1: fetch -- sysroots (VM images: not yet implemented, see STATUS)
# ---------------------------------------------------------------------------
$(SYSROOTS)/linux-amd64.tar:
	@mkdir -p $(SYSROOTS)
	fetch/build-sysroot-linux.sh amd64 $@

$(SYSROOTS)/linux-arm64.tar:
	@mkdir -p $(SYSROOTS)
	fetch/build-sysroot-linux.sh arm64 $@

fetch: $(SYSROOTS)/linux-amd64.tar $(SYSROOTS)/linux-arm64.tar
	sh vm.sh fetch freebsd_arm64
	sh vm.sh fetch netbsd_arm64
	@echo "fetch: macos_arm64 uses 'tart pull' (see provision-macos-vm.sh), not a Makefile"
	@echo "       target -- run it manually once if you haven't: tart pull ghcr.io/cirruslabs/macos-sequoia-base:latest"
	@echo "       linux_amd64_vm not yet implemented; freebsd_amd64/netbsd_amd64 frozen (see STATUS)."

# ---------------------------------------------------------------------------
# Phase 2: provision -- Docker images built+tagged once (VM provisioning:
# not yet implemented, see STATUS)
# ---------------------------------------------------------------------------
# debian:trixie-slim (13.x, frozen version 13.7) and alpine:3.24.1 (frozen
# stable) replace the previous bookworm-slim (12)/latest (floating tag) --
# per harness-target-matrix-reconciled-req and version-freshness-caching-
# policy-req (a floating tag is the anti-pattern that policy replaces).
# Not yet pulled/tested on this host -- tags are real, current Docker Hub
# tags, but this needs a `make provision` run once internet access allows.
# What the unit suite needs beyond the toolchain: pkg-config, a downloader,
# cmake/doxygen/ATF+kyua for the cases that use them, unzip/patch for fetch.
GLIBC_INSTALL := apt-get update -qq && apt-get install -y -qq --no-install-recommends bmake clang lld gcc g++ file pkgconf curl ca-certificates cmake make bison flex doxygen kyua atf-sh libatf-dev unzip patch
MUSL_INSTALL := apk add --no-cache bmake clang lld gcc g++ musl-dev file pkgconf curl cmake make bison flex doxygen kyua atf-dev unzip patch

$(IMAGES)/.linux-glibc-amd64.provisioned:
	@mkdir -p $(IMAGES)
	provision/provision-docker.sh debian:trixie-slim linux/amd64 "$(GLIBC_INSTALL)" bmk/linux-glibc:amd64
	@touch $@

$(IMAGES)/.linux-glibc-arm64.provisioned:
	@mkdir -p $(IMAGES)
	provision/provision-docker.sh debian:trixie-slim linux/arm64 "$(GLIBC_INSTALL)" bmk/linux-glibc:arm64
	@touch $@

$(IMAGES)/.linux-musl-amd64.provisioned:
	@mkdir -p $(IMAGES)
	provision/provision-docker.sh alpine:3.24.1 linux/amd64 "$(MUSL_INSTALL)" bmk/linux-musl:amd64
	@touch $@

# VM guests: vm.sh fetches the published image, prepares the read-only base
# and provisions the layer (ssh key, packages) once; see vm.sh and lib/env.sh.
$(DISKS)/layers/freebsd_arm64.qcow2:
	sh vm.sh provision freebsd_arm64

$(DISKS)/layers/netbsd_arm64.qcow2:
	sh vm.sh provision netbsd_arm64

$(IMAGES)/.macos_arm64.provisioned:
	provision/provision-macos-vm.sh
	@touch $@

provision: fetch \
	$(IMAGES)/.linux-glibc-amd64.provisioned \
	$(IMAGES)/.linux-glibc-arm64.provisioned \
	$(IMAGES)/.linux-musl-amd64.provisioned
	$(MAKE) $(DISKS)/layers/freebsd_arm64.qcow2 $(DISKS)/layers/netbsd_arm64.qcow2
	-$(MAKE) $(IMAGES)/.macos_arm64.provisioned
	@echo "provision: freebsd_amd64/netbsd_amd64 frozen (QEMU/TCG boot stall on an arm64 host);"
	@echo "           linux_amd64_vm not yet implemented -- see matrix.tsv for every cell's state."

# ---------------------------------------------------------------------------
# Phase 3 (Step A): build -- native suites, per matrix.tsv
# Phase 4 (Step B): test  -- cross cells: build for the target, run it THERE
# Phase 5: report -- the grid
# matrix.sh brings up the VMs and builds the sysroots a cell needs.
# ---------------------------------------------------------------------------
build: provision
	sh matrix.sh run 'native-*'

test: build
	sh matrix.sh run 'cross-*'

report:
	@sh matrix.sh report

vm-status:
	@sh vm.sh status

clean-cache:
	rm -rf $(CACHE)
