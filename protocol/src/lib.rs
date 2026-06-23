#![cfg_attr(not(feature = "std"), no_std)]

#[cfg(feature = "uniffi")]
uniffi::setup_scaffolding!();

/// GPS fix quality — used on the MCU to decide whether to set `differential_fix`.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum FixQuality {
    Autonomous,
    Differential,
}

/// MCU power state.
#[derive(Clone, Copy, Debug, PartialEq)]
#[repr(u8)]
#[cfg_attr(feature = "uniffi", derive(uniffi::Enum))]
pub enum McuBatteryState {
    Discharging = 0,
    Charging = 1,
    /// Plugged in and fully charged.
    Powered = 2,
}

/// A single telemetry sample streamed over BLE.
///
/// Wire format (little-endian, variable length, max 23 bytes):
///   [version u8][monotonic_ms u32][flags u8][optional fields in flag-bit order]
///
/// Flags:
///   0x01 = crank_revs       : u16
///   0x02 = lat_microdeg + lon_microdeg : i32 + i32
///   0x04 = gps_unix_time    : u32
///   0x08 = sensor_battery   : u8
///   0x10 = differential_fix : (no data, flag only)
///   0x20 = mcu_battery      : u8
///   0x40 = mcu_battery_state: u8  (McuBatteryState repr)
#[derive(Clone, Copy, Debug)]
#[cfg_attr(feature = "uniffi", derive(uniffi::Record))]
pub struct DataPoint {
    pub version: u8,
    pub monotonic_ms: u32,
    pub crank_revs: Option<u16>,
    /// Latitude in microdegrees (÷ 1_000_000 for degrees).
    pub lat_microdeg: Option<i32>,
    /// Longitude in microdegrees (÷ 1_000_000 for degrees).
    pub lon_microdeg: Option<i32>,
    pub differential_fix: bool,
    pub gps_unix_time: Option<u32>,
    /// Garmin cadence sensor battery percent.
    pub sensor_battery: Option<u8>,
    /// MCU battery percent.
    pub mcu_battery: Option<u8>,
    pub mcu_battery_state: Option<McuBatteryState>,
}

pub const PROTOCOL_VERSION: u8 = 1;

const FLAG_CRANK: u8 = 0x01;
const FLAG_LAT_LON: u8 = 0x02;
const FLAG_GPS_TIME: u8 = 0x04;
const FLAG_SENSOR_BATTERY: u8 = 0x08;
const FLAG_DIFF_FIX: u8 = 0x10;
const FLAG_MCU_BATTERY: u8 = 0x20;
const FLAG_MCU_BATTERY_STATE: u8 = 0x40;

impl DataPoint {
    pub fn pack(&self) -> heapless::Vec<u8, 24> {
        let mut buf: heapless::Vec<u8, 24> = heapless::Vec::new();
        let _ = buf.push(self.version);
        let _ = buf.extend_from_slice(&self.monotonic_ms.to_le_bytes());

        let mut flags: u8 = 0;
        if self.crank_revs.is_some() { flags |= FLAG_CRANK; }
        if self.lat_microdeg.is_some() { flags |= FLAG_LAT_LON; }
        if self.gps_unix_time.is_some() { flags |= FLAG_GPS_TIME; }
        if self.sensor_battery.is_some() { flags |= FLAG_SENSOR_BATTERY; }
        if self.differential_fix { flags |= FLAG_DIFF_FIX; }
        if self.mcu_battery.is_some() { flags |= FLAG_MCU_BATTERY; }
        if self.mcu_battery_state.is_some() { flags |= FLAG_MCU_BATTERY_STATE; }
        let _ = buf.push(flags);

        if let Some(revs) = self.crank_revs {
            let _ = buf.extend_from_slice(&revs.to_le_bytes());
        }
        if let Some(lat) = self.lat_microdeg {
            let _ = buf.extend_from_slice(&lat.to_le_bytes());
            let _ = buf.extend_from_slice(&self.lon_microdeg.unwrap_or(0).to_le_bytes());
        }
        if let Some(t) = self.gps_unix_time {
            let _ = buf.extend_from_slice(&t.to_le_bytes());
        }
        if let Some(bat) = self.sensor_battery {
            let _ = buf.push(bat);
        }
        if let Some(bat) = self.mcu_battery {
            let _ = buf.push(bat);
        }
        if let Some(state) = self.mcu_battery_state {
            let _ = buf.push(state as u8);
        }
        buf
    }

    pub fn unpack(bytes: &[u8]) -> Option<Self> {
        if bytes.len() < 6 {
            return None;
        }
        let version = bytes[0];
        if version != PROTOCOL_VERSION {
            return None;
        }
        let monotonic_ms = u32::from_le_bytes([bytes[1], bytes[2], bytes[3], bytes[4]]);
        let flags = bytes[5];
        let mut offset = 6;

        let crank_revs = if flags & FLAG_CRANK != 0 {
            if offset + 2 > bytes.len() { return None; }
            let v = u16::from_le_bytes([bytes[offset], bytes[offset + 1]]);
            offset += 2;
            Some(v)
        } else {
            None
        };

        let (lat_microdeg, lon_microdeg) = if flags & FLAG_LAT_LON != 0 {
            if offset + 8 > bytes.len() { return None; }
            let lat = i32::from_le_bytes([bytes[offset], bytes[offset+1], bytes[offset+2], bytes[offset+3]]);
            let lon = i32::from_le_bytes([bytes[offset+4], bytes[offset+5], bytes[offset+6], bytes[offset+7]]);
            offset += 8;
            (Some(lat), Some(lon))
        } else {
            (None, None)
        };

        let gps_unix_time = if flags & FLAG_GPS_TIME != 0 {
            if offset + 4 > bytes.len() { return None; }
            let v = u32::from_le_bytes([bytes[offset], bytes[offset+1], bytes[offset+2], bytes[offset+3]]);
            offset += 4;
            Some(v)
        } else {
            None
        };

        let sensor_battery = if flags & FLAG_SENSOR_BATTERY != 0 {
            if offset >= bytes.len() { return None; }
            let v = bytes[offset];
            offset += 1;
            Some(v)
        } else {
            None
        };

        let differential_fix = flags & FLAG_DIFF_FIX != 0;

        let mcu_battery = if flags & FLAG_MCU_BATTERY != 0 {
            if offset >= bytes.len() { return None; }
            let v = bytes[offset];
            offset += 1;
            Some(v)
        } else {
            None
        };

        let mcu_battery_state = if flags & FLAG_MCU_BATTERY_STATE != 0 {
            if offset >= bytes.len() { return None; }
            let state = match bytes[offset] {
                0 => McuBatteryState::Discharging,
                1 => McuBatteryState::Charging,
                2 => McuBatteryState::Powered,
                _ => return None,
            };
            Some(state)
        } else {
            None
        };

        Some(DataPoint {
            version,
            monotonic_ms,
            crank_revs,
            lat_microdeg,
            lon_microdeg,
            differential_fix,
            gps_unix_time,
            sensor_battery,
            mcu_battery,
            mcu_battery_state,
        })
    }
}

#[cfg(feature = "uniffi")]
#[uniffi::export]
fn unpack_data_point(bytes: Vec<u8>) -> Option<DataPoint> {
    DataPoint::unpack(&bytes)
}
