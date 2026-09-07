#!/bin/sh
set -eu
cd ws
out=$(bmake help)
echo "$out" | grep -q "PARENT_WS="

cd Fw
out=$(bmake help)
echo "$out" | grep -q "PREREQS="

cd p.m
out=$(bmake help)
echo "$out" | grep -q "PROG="

echo "help target OK"
