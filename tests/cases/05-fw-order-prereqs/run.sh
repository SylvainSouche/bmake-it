#!/bin/sh
set -eu
cd ws
sh "${BMK_SCRIPTS}/gen-fw-order.sh" .order.mk
cat .order.mk
order=$(sed -n 's/^FRAMEWORK_SUBDIR=//p' .order.mk)
echo "order=$order"
echo "$order" | awk '{
  for(i=1;i<=NF;i++) pos[$i]=i
  if(pos["A"] < pos["B"] && pos["B"] < pos["C"]) exit 0
  exit 1
}'
