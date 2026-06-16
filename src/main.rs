#![no_std]
#![no_main]

use core::fmt::Write;
use display_interface::DisplayError;
use embassy_executor::{SpawnError, Spawner};
use embassy_nrf::gpio::{Level, Output, OutputDrive};
use embassy_nrf::peripherals::USBD;
use embassy_nrf::usb::vbus_detect::HardwareVbusDetect;
use embassy_nrf::usb::Driver;
use embassy_nrf::{bind_interrupts, peripherals, twim, usb};
use embassy_time::Timer;
use embassy_usb::class::cdc_acm::{CdcAcmClass, State};
use embassy_usb::driver::EndpointError;
use embassy_usb::UsbDevice;
use embedded_graphics::{
    mono_font::{ascii::FONT_6X10, MonoTextStyleBuilder},
    pixelcolor::BinaryColor,
    prelude::*,
    text::{Baseline, Text},
};
use heapless::String;
use panic_halt as _;
use ssd1306::{prelude::*, I2CDisplayInterface, Ssd1306};
use static_cell::StaticCell;

bind_interrupts!(struct Irqs {
    USBD => usb::InterruptHandler<peripherals::USBD>;
    CLOCK_POWER => usb::vbus_detect::InterruptHandler;
    TWISPI0 => twim::InterruptHandler<peripherals::TWISPI0>;
});

type MyDriver = Driver<'static, peripherals::USBD, HardwareVbusDetect>;

#[embassy_executor::main]
async fn main(spawner: Spawner) {
    let p = embassy_nrf::init(Default::default());

    let mut red = Output::new(p.P0_26, Level::High, OutputDrive::Standard);

    let mut usb = Usb::new(p.USBD, spawner).expect("failed to initialize USB");

    loop {
        // Wait for host to connect (DTR = Data Terminal Ready)
        usb.wait_connection().await;

        Timer::after_millis(100).await;
        let screen = Screen::new(p.TWISPI0, p.P0_04, p.P0_05);
        match &screen {
            Ok(_) => {
                usb.write_packet(b"screen: ok\r\n").await.ok();
            }
            Err(e) => {
                let mut buf: String<64> = String::new();
                write!(buf, "screen error: {:?}\r\n", e).unwrap();
                usb.write_packet(buf.as_bytes()).await.ok();
            }
        };

        loop {
            red.set_low();
            Timer::after_millis(500).await;
            red.set_high();
            Timer::after_millis(500).await;
        }
    }
}

struct Screen {}

impl Screen {
    pub fn new(
        i2c: peripherals::TWISPI0,
        sda: peripherals::P0_04,
        scl: peripherals::P0_05,
    ) -> Result<Self, DisplayError> {
        let i2c = twim::Twim::new(i2c, Irqs, sda, scl, twim::Config::default());
        let interface = I2CDisplayInterface::new(i2c);
        let mut display = Ssd1306::new(interface, DisplaySize128x64, DisplayRotation::Rotate0)
            .into_buffered_graphics_mode();
        display.init()?;

        let text_style = MonoTextStyleBuilder::new()
            .font(&FONT_6X10)
            .text_color(BinaryColor::On)
            .build();

        Text::with_baseline("Hello!", Point::zero(), text_style, Baseline::Top)
            .draw(&mut display)
            .unwrap();

        display.flush()?;
        Ok(Self {})
    }
}

struct Usb {
    class: CdcAcmClass<'static, MyDriver>,
}

impl Usb {
    pub fn new(usbd: USBD, spawner: Spawner) -> Result<Self, SpawnError> {
        // USB driver — hands the hardware peripheral to embassy-usb
        let driver = Driver::new(usbd, Irqs, HardwareVbusDetect::new(Irqs));

        // Buffers the USB stack needs — must be 'static
        static STATE: StaticCell<State> = StaticCell::new();
        static CONFIG_DESCRIPTOR: StaticCell<[u8; 256]> = StaticCell::new();
        static BOS_DESCRIPTOR: StaticCell<[u8; 256]> = StaticCell::new();
        static MSOS_DESCRIPTOR: StaticCell<[u8; 256]> = StaticCell::new();
        static CONTROL_BUF: StaticCell<[u8; 64]> = StaticCell::new();

        let state = STATE.init(State::new());
        let config_desc = CONFIG_DESCRIPTOR.init([0u8; 256]);
        let bos_desc = BOS_DESCRIPTOR.init([0u8; 256]);
        let msos_desc = MSOS_DESCRIPTOR.init([0u8; 256]);
        let control_buf = CONTROL_BUF.init([0u8; 64]);

        // Describe the USB device
        let mut config = embassy_usb::Config::new(0xc0de, 0xcafe);
        config.manufacturer = Some("Nikita");
        config.product = Some("Bike Computer");
        config.serial_number = Some("1");
        config.max_power = 100;

        // Build the USB device + attach CDC ACM class
        let mut builder = embassy_usb::Builder::new(
            driver,
            config,
            config_desc,
            bos_desc,
            msos_desc,
            control_buf,
        );
        let class = CdcAcmClass::new(&mut builder, state, 64);
        let usb = builder.build();

        #[embassy_executor::task]
        async fn usb_task(mut device: UsbDevice<'static, MyDriver>) {
            device.run().await;
        }

        spawner.spawn(usb_task(usb))?;
        Ok(Self { class })
    }

    pub async fn wait_connection(&mut self) {
        self.class.wait_connection().await
    }

    pub async fn write_packet(&mut self, data: &[u8]) -> Result<(), EndpointError> {
        self.class.write_packet(data).await
    }
}
