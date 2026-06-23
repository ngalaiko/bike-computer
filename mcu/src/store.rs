use embassy_futures::select::{select4, Either4};
use embassy_sync::blocking_mutex::raw::CriticalSectionRawMutex;
use embassy_sync::mutex::Mutex;
use embassy_sync::watch::Watch;
use embassy_time::Instant;
use heapless::Deque;

use crate::gps::FixQuality;
pub use voop_protocol::DataPoint;

const CAPACITY: usize = 4096;

struct Store {
    buf: Deque<DataPoint, CAPACITY>,
}

impl Store {
    const fn new() -> Self {
        Self { buf: Deque::new() }
    }

    fn push(&mut self, point: DataPoint) {
        if self.buf.is_full() {
            self.buf.pop_front();
        }
        let _ = self.buf.push_back(point);
    }

    fn peek_latest(&self) -> Option<DataPoint> {
        self.buf.back().copied()
    }

    fn pop_newest(&mut self) -> Option<DataPoint> {
        self.buf.pop_back()
    }
}

static STORE: Mutex<CriticalSectionRawMutex, Store> = Mutex::new(Store::new());

/// Fires () whenever a new DataPoint is pushed. 2 receivers: screen + peripheral.
pub static UPDATED: Watch<CriticalSectionRawMutex, (), 2> = Watch::new();

pub async fn peek_latest() -> Option<DataPoint> {
    STORE.lock().await.peek_latest()
}

pub async fn pop_newest() -> Option<DataPoint> {
    STORE.lock().await.pop_newest()
}

pub async fn run() {
    let Some(mut crank_rx) = crate::ble::CRANK_REVS.receiver() else {
        log::error!("[Store] CRANK_REVS: no free receiver slot");
        return;
    };
    let Some(mut battery_rx) = crate::ble::BATTERY.receiver() else {
        log::error!("[Store] BATTERY: no free receiver slot");
        return;
    };
    let Some(mut location_rx) = crate::gps::LOCATION.receiver() else {
        log::error!("[Store] LOCATION: no free receiver slot");
        return;
    };
    let Some(mut time_rx) = crate::gps::TIME.receiver() else {
        log::error!("[Store] TIME: no free receiver slot");
        return;
    };

    let mut current_lat: Option<i32> = None;
    let mut current_lon: Option<i32> = None;
    let mut current_fix_quality: Option<FixQuality> = None;
    let mut current_gps_time: Option<u32> = None;
    let mut current_battery: Option<u8> = None;

    loop {
        match select4(
            crank_rx.changed(),
            battery_rx.changed(),
            location_rx.changed(),
            time_rx.changed(),
        )
        .await
        {
            Either4::First(Ok(revs)) => {
                let point = DataPoint {
                    version: voop_protocol::PROTOCOL_VERSION,
                    monotonic_ms: Instant::now().as_millis() as u32,
                    crank_revs: Some(revs),
                    lat_microdeg: current_lat,
                    lon_microdeg: current_lon,
                    differential_fix: matches!(current_fix_quality, Some(FixQuality::Differential)),
                    gps_unix_time: current_gps_time,
                    sensor_battery: current_battery,
                    mcu_battery: None,
                    mcu_battery_state: None,
                };
                STORE.lock().await.push(point);
                UPDATED.sender().send(());
            }
            Either4::First(Err(_)) => {}
            Either4::Second(Ok(bat)) => {
                current_battery = Some(bat);
            }
            Either4::Second(Err(_)) => {}
            Either4::Third(Ok(loc)) => {
                current_lat = Some((loc.lat * 1_000_000.0) as i32);
                current_lon = Some((loc.lon * 1_000_000.0) as i32);
                current_fix_quality = Some(loc.fix_quality);
            }
            Either4::Third(Err(_)) => {}
            Either4::Fourth(Ok(t)) => {
                current_gps_time = Some(t);
            }
            Either4::Fourth(Err(_)) => {}
        }
    }
}
