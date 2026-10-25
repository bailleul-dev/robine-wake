#!/bin/sh
# Runs system.cir for each variant and prints one line per variant.
# usb_V is the S3 5 V rail, usb_mA the current the USB port gives, usb_in_mA the current
# pushed back into it (JP4 closed with the USB cable plugged).
cd "$(dirname "$0")"
printf '%-34s %6s %6s %6s %6s %6s %6s %7s %7s %6s\n' variant s3_5V e5_V s3_3V3 e32_3V3 usb_mA in_mA vdd_min margin i2c_ns
# fields: D1 buffer strip_A single buck usb_V
for v in "1 0 3.4 0 0 5.0" "0 0 3.4 0 0 5.0" "2 0 3.4 0 0 5.0" "1 1 3.4 0 0 5.0" "0 1 3.4 0 0 5.0" "2 1 3.4 0 0 5.0" \
         "0 1 3.4 1 0 0" "0 1 3.4 1 1 0" "0 1 3.4 1 2 0" \
         "0 1 3.4 1 2 4.75" "0 1 3.4 1 2 5.0" "0 1 3.4 1 2 5.25"; do
  set -- $v
  if [ "$4" = 1 ] && [ "$6" = 0 ]; then usb="VUSB=0 RUSB=1G"; usbname=; else usb="VUSB=$6 RUSB=0.4"; usbname=; fi
  [ "$6" != 0 ] && [ "$6" != 5.0 -o "$4" = 1 ] && usbname=" usb$6"
  case $5 in
    1) bk="LB=47u CB=220u ESRB=80m HY=0.5 KP=6.9 KI=4.3e4"; te=3m; src="buck-slow";;
    2) bk="LB=10u CB=47u ESRB=5m HY=0.3 KP=5.9 KI=1.5e5"; te=3m; src="buck-fast";;
    *) bk="LB=47u CB=220u ESRB=80m HY=0.5 KP=6.9 KI=4.3e4"; te=1.3m; if [ "$4" = 1 ]; then src="single"; else src="3src"; fi;;
  esac
  sed "s/^\.param USE_D1=.*/.param USE_D1=$1 USE_BUF=$2 I_STRIP=$3 $usb R3V=330 R1V=2.2k SINGLE=$4 BUCK=$5/; s/^\.param LB=.*/.param $bk/; /^\.tran/s/1\.3m/$te/; /^meas/s/to=1\.3m/to=$te/" system.cir > /tmp/s3_run.cir
  out=$(ngspice -b /tmp/s3_run.cir 2>&1)
  g() { echo "$out" | grep -E "^$1 +=" | head -1 | sed 's/^[^=]*= *//' | awk '{print $1}'; }
  printf '%-34s %6.2f %6.2f %6.2f %6.2f %6.0f %6.0f %7.2f %7.2f %6.0f\n' "D1=$1 buf=$2 $3A $src$usbname" "$(g usb_min)" "$(g e5_min)" "$(g s33_min)" "$(g e33_min)" "$(g iusb_max | awk '{print -1000*$1}')" "$(g iusb_in | awk '{print 1000*$1}')" "$(g vdd_min)" "$(echo "$out" | grep -E '^margin' | tail -1 | sed 's/.*= *//' | awk '{print $1}')" "$(g i2c_rise | awk '{print 1e9*$1}')"
done
