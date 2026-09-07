#!/bin/sh
set -eu
cd ws/Fw
bmake -C p.m all
echo "CFLAGS append OK"
