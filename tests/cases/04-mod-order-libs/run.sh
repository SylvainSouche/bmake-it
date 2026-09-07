#!/bin/sh
set -eu
cd ws/Fw
# Ensure gen-mod-order produces base before mid before top
sh "${BMK_SCRIPTS}/gen-mod-order.sh" .order.mk
cat .order.mk
# Extract SUBDIR order
order=$(sed -n 's/^MODULE_SUBDIR=//p' .order.mk)
echo "order=$order"
# base must appear before mid, mid before top
echo "$order" | awk '{
  for(i=1;i<=NF;i++) pos[$i]=i
  if(pos["libbase.m"] < pos["mid.m"] && pos["mid.m"] < pos["top.m"]) exit 0
  exit 1
}'
