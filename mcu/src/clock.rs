use embassy_sync::blocking_mutex::raw::CriticalSectionRawMutex;
use embassy_sync::mutex::Mutex;
use embassy_time::Instant;

pub use voop_protocol::Time;

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

/// Current time. Returns Unix seconds if a sync anchor has been set, otherwise
/// monotonic milliseconds since boot.
pub async fn now() -> Time {
    let now_mono = Instant::now().as_millis() as u32;
    match *ANCHOR.lock().await {
        None => Time::Monotonic { ms: now_mono },
        Some(ref anchor) => {
            Time::Unix { seconds: anchor.unix_s.saturating_add((now_mono - anchor.mono_ms) / 1000) }
        }
    }
}
