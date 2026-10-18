#![no_std]
#![no_main]

use core::fmt::Write;
use esp8266_hal::prelude::*;
use esp8266_hal::target::Peripherals;
use panic_halt as _;

#[entry]
fn main() -> ! {
    let dp = Peripherals::take().unwrap();
    let pins = dp.GPIO.split();
    // LED bleue du module ESP-12, allumée à l'état bas.
    let mut led = pins.gpio2.into_push_pull_output();
    let mut serial = dp
        .UART0
        .serial(pins.gpio1.into_uart(), pins.gpio3.into_uart());
    let (mut timer1, _) = dp.TIMER.timers();

    let mut tick: u32 = 0;
    loop {
        led.toggle().unwrap();
        write!(serial, "robine esp8266: tick {}\r\n", tick).unwrap();
        tick = tick.wrapping_add(1);
        timer1.delay_ms(500);
    }
}
