#!/bin/sh
set -eu
cd ws
key1=$(bmake -V OS_ARCH TARGET=linux TARGET_ARCH=amd64)
echo "key1=$key1"
[ "$key1" = "linux-amd64" ]
key2=$(bmake -V OS_ARCH TARGET=linux TARGET_ARCH=amd64 ABI=musl)
echo "key2=$key2"
[ "$key2" = "linux-amd64-musl" ]
echo "linux target-key ABI OK"
