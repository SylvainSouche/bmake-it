#!/bin/sh
set -eu
cd ws/Fw
sh "${BMK_SCRIPTS}/gen-mod-order.sh" .order.mk
grep -q 'only.m' .order.mk
echo "external LIBS ignored OK"
