#!/bin/sh
# Runs system.cir for each variant and prints one line per variant.
cd "$(dirname "$0")"
printf '%-34s %7s %7s %7s %8s %8s\n' variant vin_min v33_min vdd_strip margin bit1_ns
for v in "1 0 3.4" "0 0 3.4" "1 1 3.4" "0 1 3.4" "1 0 1.8" "1 1 1.8" "1 1 1.0"; do
  set -- $v
  sed "s/^\.param USE_D1=.*/.param USE_D1=$1 USE_BUF=$2 I_STRIP=$3 VPI=4.85 R3V=330/" system.cir > /tmp/system_run.cir
  out=$(ngspice -b /tmp/system_run.cir 2>&1)
  g() { echo "$out" | grep -E "^$1 +=" | head -1 | sed 's/^[^=]*= *//' | awk '{print $1}'; }
  printf '%-34s %7.2f %7.2f %7.2f %8.2f %8s\n' "D1=$1 buffer=$2 strip=$3A" "$(g vin_min)" "$(g v33_min)" "$(g vdd)" "$(echo "$out" | grep -E '^margin' | tail -1 | sed 's/.*= *//' | awk '{print $1}')" "$(g width | awk '{printf "%d", $1*1e9}')"
done
