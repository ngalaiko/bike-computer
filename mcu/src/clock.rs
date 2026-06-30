use embassy_sync::blocking_mutex::raw::CriticalSectionRawMutex;
use embassy_sync::mutex::Mutex;
use embassy_time::Instant;

/// The raw clock state at one instant: the always-available monotonic uptime, plus the
/// wall-clock estimate when an anchor has been set. Stamped onto every DataPoint so iOS
/// reconstructs the timeline itself.
#[derive(Clone, Copy)]
pub struct ClockReading {
    pub uptime_ms: u32,
    pub unix_millis: Option<u64>,
}

struct Anchor {
    mono_ms: u32,
    unix_s: u32,
}

static ANCHOR: Mutex<CriticalSectionRawMutex, Option<Anchor>> = Mutex::new(None);

/// Record a wall-clock anchor. Call when iOS writes a time sync or when GPS fixes.
/// GPS should be preferred — call again when a fix arrives to improve accuracy.
pub async fn set(unix_seconds: u32) {
    let mono_ms = Instant::now().as_millis() as u32;
    *ANCHOR.lock().await = Some(Anchor { mono_ms, unix_s: unix_seconds });
}

/// Current clock reading: always the monotonic uptime, plus a wall-clock estimate once an
/// anchor exists. The anchor is only second-accurate (iOS/GPS sync it in whole seconds);
/// the sub-second part comes from the monotonic delta, so consecutive `unix_millis` deltas
/// stay ms-precise — and the raw `uptime_ms` is reported regardless for the consumer to use.
pub async fn now() -> ClockReading {
    let uptime_ms = Instant::now().as_millis() as u32;
    let unix_millis = ANCHOR
        .lock()
        .await
        .as_ref()
        .map(|a| (a.unix_s as u64) * 1000 + uptime_ms.wrapping_sub(a.mono_ms) as u64);
    ClockReading { uptime_ms, unix_millis }
}
