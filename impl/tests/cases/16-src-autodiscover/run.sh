#!/bin/sh
set -eu
cd ws/Fw
srcs=$(bmake -C p.m -V SRCS)
echo "SRCS=$srcs"
echo "$srcs" | grep -q 'a.c'
echo "$srcs" | grep -q 'main.c'
bmake -C p.m all
echo "src autodiscover OK"
