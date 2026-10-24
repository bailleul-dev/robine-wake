#!/bin/sh
# Runs system.cir for each variant and prints one line per variant.
cd "$(dirname "$0")"
printf '%-30s %6s %6s %6s %6s %6s %7s %6s\n' variant usb_V e5_V s3_3V3 e32_3V3 usb_mA margin i2c_ns
for v in "1 0 3.4" "0 0 3.4" "2 0 3.4" "1 1 3.4" "0 1 3.4" "2 1 3.4"; do
  set -- $v
  sed "s/^\.param USE_D1=.*/.param USE_D1=$1 USE_BUF=$2 I_STRIP=$3 VUSB=5.0 RUSB=0.4 R3V=330 R1V=4.7k/" system.cir > /tmp/s3_run.cir
  out=$(ngspice -b /tmp/s3_run.cir 2>&1)
  g() { echo "$out" | grep -E "^$1 +=" | head -1 | sed 's/^[^=]*= *//' | awk '{print $1}'; }
  printf '%-30s %6.2f %6.2f %6.2f %6.2f %6.0f %7.2f %6.0f\n' "D1=$1 buffer=$2 strip=$3A" "$(g usb_min)" "$(g e5_min)" "$(g s33_min)" "$(g e33_min)" "$(echo "$(g iusb_max) * -1000" | bc -l)" "$(echo "$out" | grep -E '^margin' | tail -1 | sed 's/.*= *//' | awk '{print $1}')" "$(echo "$(g i2c_rise) * 1000000000" | bc -l)"
done
