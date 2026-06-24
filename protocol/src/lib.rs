#![cfg_attr(not(feature = "std"), no_std)]

#[cfg(feature = "uniffi")]
uniffi::setup_scaffolding!();

pub const SERVICE_UUID: &str = "bece0001-ede4-4b59-8c60-1ee44d963a05";
/// Notify: streams DataPoints during a ride.
pub const STREAM_CHAR_UUID: &str = "bece0002-ede4-4b59-8c60-1ee44d963a05";
/// Read: current MCU and sensor status snapshot.
pub const STATUS_CHAR_UUID: &str = "bece0003-ede4-4b59-8c60-1ee44d963a05";
/// Write: iOS sends current unix time to the MCU.
pub const TIME_SYNC_CHAR_UUID: &str = "bece0004-ede4-4b59-8c60-1ee44d963a05";

#[derive(Clone, Copy, Debug, PartialEq)]
#[repr(u8)]
#[cfg_attr(feature = "uniffi", derive(uniffi::Enum))]
pub enum BatteryState {
    Charging = 0,
    Discharging = 1,
}

#[derive(Clone, Copy, Debug, PartialEq)]
#[cfg_attr(feature = "uniffi", derive(uniffi::Record))]
pub struct BatteryStatus {
    pub percent: u8,
    pub state: BatteryState,
}

/// Snapshot read from the STATUS_CHAR_UUID characteristic.
///
/// Wire format (4 bytes, fixed):
///   [mcu_percent u8][mcu_state u8][flags u8][sensor_battery u8]
///   flags: bit 0 = sensor_connected, bit 1 = sensor_battery_present
#[derive(Clone, Copy, Debug)]
#[cfg_attr(feature = "uniffi", derive(uniffi::Record))]
pub struct DeviceStatus {
    pub mcu_battery: BatteryStatus,
    pub sensor_connected: bool,
    /// Sensor battery percent. None if sensor is not connected or level unknown.
    pub sensor_battery: Option<u8>,
}

impl DeviceStatus {
    pub fn pack(&self) -> [u8; 4] {
        let mut flags: u8 = 0;
        if self.sensor_connected { flags |= 0x01; }
        if self.sensor_battery.is_some() { flags |= 0x02; }
        [
            self.mcu_battery.percent,
            self.mcu_battery.state as u8,
            flags,
            self.sensor_battery.unwrap_or(0xFF),
        ]
    }

    pub fn unpack(bytes: &[u8]) -> Option<Self> {
        if bytes.len() < 4 { return None; }
        let state = match bytes[1] {
            0 => BatteryState::Charging,
            1 => BatteryState::Discharging,
            _ => return None,
        };
        let flags = bytes[2];
        Some(DeviceStatus {
            mcu_battery: BatteryStatus { percent: bytes[0], state },
            sensor_connected: flags & 0x01 != 0,
            sensor_battery: if flags & 0x02 != 0 { Some(bytes[3]) } else { None },
        })
    }
}

/// Time carried in each DataPoint.
// uniffi requires named fields in enum variants.
#[derive(Clone, Copy, Debug)]
#[cfg_attr(feature = "uniffi", derive(uniffi::Enum))]
pub enum Time {
    /// Milliseconds since MCU boot. Used before iOS has written a time sync.
    Monotonic { ms: u32 },
    /// Seconds since Unix epoch. Used after iOS writes TIME_SYNC_CHAR_UUID.
    Unix { seconds: u32 },
}

/// A single telemetry sample streamed over STREAM_CHAR_UUID.
///
/// Wire format (little-endian, variable, 5–15 bytes):
///   [flags u8][time u32][lat i32?][lon i32?][crank_revs u16?]
///   flags: bit 0 = unix time (else monotonic), bit 1 = coords, bit 2 = crank_revs
#[derive(Clone, Copy, Debug)]
#[cfg_attr(feature = "uniffi", derive(uniffi::Record))]
pub struct DataPoint {
    pub time: Time,
    pub lat_microdeg: Option<i32>,
    pub lon_microdeg: Option<i32>,
    pub crank_revs: Option<u16>,
}

const FLAG_UNIX: u8 = 0x01;
const FLAG_COORDS: u8 = 0x02;
const FLAG_CRANK: u8 = 0x04;

impl DataPoint {
    pub fn pack(&self) -> heapless::Vec<u8, 15> {
        let mut buf: heapless::Vec<u8, 15> = heapless::Vec::new();
        let mut flags: u8 = 0;
        if matches!(self.time, Time::Unix { .. }) { flags |= FLAG_UNIX; }
        if self.lat_microdeg.is_some() { flags |= FLAG_COORDS; }
        if self.crank_revs.is_some() { flags |= FLAG_CRANK; }
        let _ = buf.push(flags);
        let time_val = match self.time {
            Time::Monotonic { ms } => ms,
            Time::Unix { seconds } => seconds,
        };
        let _ = buf.extend_from_slice(&time_val.to_le_bytes());
        if let Some(lat) = self.lat_microdeg {
            let _ = buf.extend_from_slice(&lat.to_le_bytes());
            let _ = buf.extend_from_slice(&self.lon_microdeg.unwrap_or(0).to_le_bytes());
        }
        if let Some(revs) = self.crank_revs {
            let _ = buf.extend_from_slice(&revs.to_le_bytes());
        }
        buf
    }

    pub fn unpack(bytes: &[u8]) -> Option<Self> {
        if bytes.len() < 5 { return None; }
        let flags = bytes[0];
        let time_val = u32::from_le_bytes([bytes[1], bytes[2], bytes[3], bytes[4]]);
        let time = if flags & FLAG_UNIX != 0 {
            Time::Unix { seconds: time_val }
        } else {
            Time::Monotonic { ms: time_val }
        };
        let mut offset = 5;
        let (lat_microdeg, lon_microdeg) = if flags & FLAG_COORDS != 0 {
            if offset + 8 > bytes.len() { return None; }
            let lat = i32::from_le_bytes([bytes[offset], bytes[offset+1], bytes[offset+2], bytes[offset+3]]);
            let lon = i32::from_le_bytes([bytes[offset+4], bytes[offset+5], bytes[offset+6], bytes[offset+7]]);
            offset += 8;
            (Some(lat), Some(lon))
        } else {
            (None, None)
        };
        let crank_revs = if flags & FLAG_CRANK != 0 {
            if offset + 2 > bytes.len() { return None; }
            Some(u16::from_le_bytes([bytes[offset], bytes[offset + 1]]))
        } else {
            None
        };
        Some(DataPoint { time, lat_microdeg, lon_microdeg, crank_revs })
    }
}

#[cfg(feature = "uniffi")]
#[uniffi::export]
fn service_uuid() -> String { SERVICE_UUID.to_string() }

#[cfg(feature = "uniffi")]
#[uniffi::export]
fn stream_char_uuid() -> String { STREAM_CHAR_UUID.to_string() }

#[cfg(feature = "uniffi")]
#[uniffi::export]
fn status_char_uuid() -> String { STATUS_CHAR_UUID.to_string() }

#[cfg(feature = "uniffi")]
#[uniffi::export]
fn time_sync_char_uuid() -> String { TIME_SYNC_CHAR_UUID.to_string() }

#[cfg(feature = "uniffi")]
#[uniffi::export]
fn unpack_data_point(bytes: Vec<u8>) -> Option<DataPoint> {
    DataPoint::unpack(&bytes)
}

#[cfg(feature = "uniffi")]
#[uniffi::export]
fn unpack_device_status(bytes: Vec<u8>) -> Option<DeviceStatus> {
    DeviceStatus::unpack(&bytes)
}
