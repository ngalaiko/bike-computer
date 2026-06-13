#![no_std]
#![no_main]

use embassy_executor::Spawner;
use embassy_nrf::gpio::{Level, Output, OutputDrive};
use embassy_time::Timer;
use panic_halt as _;

#[embassy_executor::main]
async fn main(_spawner: Spawner) {
    let p = embassy_nrf::init(Default::default());
    let mut red = Output::new(p.P0_26, Level::High, OutputDrive::Standard);
    let mut green = Output::new(p.P0_30, Level::High, OutputDrive::Standard);
    let mut blue = Output::new(p.P0_06, Level::High, OutputDrive::Standard);

    loop {
        red.set_low();
        Timer::after_millis(500).await;
        red.set_high();
        Timer::after_millis(500).await;

        red.set_low();
        Timer::after_millis(500).await;
        red.set_high();
        Timer::after_millis(500).await;

        green.set_low();
        Timer::after_millis(500).await;
        green.set_high();
        Timer::after_millis(500).await;

        blue.set_low();
        Timer::after_millis(500).await;
        blue.set_high();
        Timer::after_millis(500).await;
    }
}
