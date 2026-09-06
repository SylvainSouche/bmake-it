#!/bin/sh
set -eu
cd ws
out=$(bmake -V SUBDIR_FRAMEWORKS)
echo "discovered: $out"
echo "$out" | grep -q EmptyFw
mkdir -p build distrib
out2=$(bmake -V SUBDIR_FRAMEWORKS)
echo "with build/distrib present: $out2"
echo "$out2" | grep -q EmptyFw
case " $out2 " in
  *" build "*|*" distrib "*) echo "build/distrib wrongly discovered" >&2; exit 1 ;;
esac
