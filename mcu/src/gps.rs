use chrono::{Datelike as _, Timelike as _};
use embassy_nrf::uarte::{self, Uarte};
use embassy_nrf::{peripherals, Peri};
use embassy_sync::blocking_mutex::raw::CriticalSectionRawMutex;
use embassy_sync::watch::Watch;

#[derive(Clone, Copy)]
pub struct GpsState {
    pub lat_microdeg: i32,
    pub lon_microdeg: i32,
}

pub static GPS: Watch<CriticalSectionRawMutex, GpsState, 2> = Watch::new();

#[derive(Clone, Copy, Debug, PartialEq)]
enum FixQuality {
    Autonomous,
    Differential,
}

pub struct Gps {
    uarte0: Peri<'static, peripherals::UARTE0>,
    txd: Peri<'static, peripherals::P1_11>,
    rxd: Peri<'static, peripherals::P1_12>,
    timer1: Peri<'static, peripherals::TIMER1>,
    ppi_ch0: Peri<'static, peripherals::PPI_CH0>,
    ppi_ch1: Peri<'static, peripherals::PPI_CH1>,
}

pub fn init(
    uarte0: Peri<'static, peripherals::UARTE0>,
    txd: Peri<'static, peripherals::P1_11>,
    rxd: Peri<'static, peripherals::P1_12>,
    timer1: Peri<'static, peripherals::TIMER1>,
    ppi_ch0: Peri<'static, peripherals::PPI_CH0>,
    ppi_ch1: Peri<'static, peripherals::PPI_CH1>,
) -> Gps {
    Gps { uarte0, txd, rxd, timer1, ppi_ch0, ppi_ch1 }
}

impl Gps {
    pub async fn run(self) {
        let mut config = uarte::Config::default();
        config.baudrate = uarte::Baudrate::BAUD9600;
        let uarte = Uarte::new(self.uarte0, self.rxd, self.txd, crate::Irqs, config);
        let (_tx, mut rx) = uarte.split_with_idle(self.timer1, self.ppi_ch0, self.ppi_ch1);

        let gps_tx = GPS.sender();

        let mut buf = [0u8; 1024];
        loop {
            match rx.read_until_idle(&mut buf).await {
                Ok(n) => {
                    for line in buf[..n].split(|&b| b == b'\n') {
                        if line.is_empty() {
                            continue;
                        }
                        match nmea::parse_bytes(line) {
                            Ok(nmea::ParseResult::RMC(rmc)) => {
                                let fix_quality = match rmc.status_of_fix {
                                    nmea::sentences::rmc::RmcStatusOfFix::Autonomous => {
                                        Some(FixQuality::Autonomous)
                                    }
                                    nmea::sentences::rmc::RmcStatusOfFix::Differential => {
                                        Some(FixQuality::Differential)
                                    }
                                    _ => None,
                                };
                                if let (Some(_fix), Some(lat), Some(lon)) =
                                    (fix_quality, rmc.lat, rmc.lon)
                                {
                                    gps_tx.send(GpsState {
                                        lat_microdeg: (lat * 1_000_000.0) as i32,
                                        lon_microdeg: (lon * 1_000_000.0) as i32,
                                    });
                                }
                                if let (Some(date), Some(time)) = (rmc.fix_date, rmc.fix_time) {
                                    let epoch = to_unix_epoch(
                                        date.year(),
                                        date.month() as u8,
                                        date.day() as u8,
                                        time.hour() as u8,
                                        time.minute() as u8,
                                        time.second() as u8,
                                    );
                                    crate::clock::set(epoch).await;
                                }
                            }
                            Ok(_) | Err(_) => {}
                        }
                    }
                }
                Err(e) => log::debug!("[GPS] read error: {:?}", e),
            }
        }
    }
}

// Howard Hinnant's civil-to-days algorithm → Unix epoch.
fn to_unix_epoch(year: i32, month: u8, day: u8, hour: u8, minute: u8, second: u8) -> u32 {
    let y = year - if month <= 2 { 1 } else { 0 };
    let era = y.div_euclid(400);
    let yoe = y.rem_euclid(400) as u32;
    let m = month as u32;
    let doy = (153 * (if m > 2 { m - 3 } else { m + 9 }) + 2) / 5 + day as u32 - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    let days = era * 146097 + doe as i32 - 719468;
    days as u32 * 86400 + hour as u32 * 3600 + minute as u32 * 60 + second as u32
}
