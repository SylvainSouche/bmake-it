#!/bin/sh
set -eu
cd ws
k1=$(bmake -V OS_ARCH)
echo "default OS_ARCH=$k1"
echo "$k1" | grep -qv -- '-llvm'
k2=$(bmake TOOLCHAIN=gcc -V OS_ARCH)
echo "gcc OS_ARCH=$k2"
echo "$k2" | grep -q -- '-gcc'
k3=$(bmake TARGET=freebsd TARGET_ARCH=amd64 -V OS_ARCH)
echo "freebsd OS_ARCH=$k3"
[ "$k3" = "freebsd-amd64" ]
