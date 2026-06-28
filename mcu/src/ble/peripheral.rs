use embassy_futures::join::join;
use embassy_futures::select::{select, select4, Either, Either4};
use embassy_sync::blocking_mutex::raw::CriticalSectionRawMutex;
use embassy_sync::mutex::Mutex;
use embassy_sync::signal::Signal;
use embassy_sync::watch::Watch;
use embassy_time::{Duration, Ticker, with_timeout};
use heapless::Deque;
use static_cell::StaticCell;
use trouble_host::prelude::*;
use voop_protocol::{BatteryState, BatteryStatus, DataPoint, DeviceStatus};

#[gatt_server]
pub struct BikeServer {
    bike: BikeService,
}

#[gatt_service(uuid = "bece0001-ede4-4b59-8c60-1ee44d963a05")]
struct BikeService {
    /// Packed DataPoint wire format, max 15 bytes. See voop_protocol::DataPoint::pack().
    #[characteristic(uuid = "bece0002-ede4-4b59-8c60-1ee44d963a05", notify, value = [0u8; 15])]
    stream: [u8; 15],
    /// Current device status snapshot. See voop_protocol::DeviceStatus::pack().
    #[characteristic(uuid = "bece0003-ede4-4b59-8c60-1ee44d963a05", read, notify, value = [100u8, 0u8, 0u8, 0xFFu8])]
    status: [u8; 4],
    /// iOS writes current unix timestamp (u32 LE) to sync the MCU clock.
    #[characteristic(uuid = "bece0004-ede4-4b59-8c60-1ee44d963a05", write, value = [0u8; 4])]
    time_sync: [u8; 4],
}

// Legacy ADV data: flags + 128-bit service UUID + complete local name.
// UUID bece0001-ede4-4b59-8c60-1ee44d963a05 in LE: 05 3a 96 4d e4 1e 60 8c 59 4b e4 ed 01 00 ce be
const ADV_DATA: &[u8] = &[
    0x02, 0x01, 0x06,
    0x11, 0x07,
    0x05, 0x3A, 0x96, 0x4D, 0xE4, 0x1E, 0x60, 0x8C, 0x59, 0x4B, 0xE4, 0xED, 0x01, 0x00, 0xCE,
    0xBE, 0x05, 0x09, b'V', b'o', b'o', b'p',
];

/// Whether iOS is currently connected as a GATT client.
/// 1 receiver: screen.
pub static IOS_CONNECTED: Watch<CriticalSectionRawMutex, bool, 1> = Watch::new();

// Ring buffer of DataPoints to replay when iOS reconnects.
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

    fn pop_newest(&mut self) -> Option<DataPoint> {
        self.buf.pop_back()
    }
}

static STORE: Mutex<CriticalSectionRawMutex, Store> = Mutex::new(Store::new());

// Signals the latest DataPoint to the live-streaming loop when iOS is connected.
static LIVE: Signal<CriticalSectionRawMutex, DataPoint> = Signal::new();

// Current sensor state — updated by the DataPoint loop, read by the iOS loop for DeviceStatus.
struct SensorState {
    connected: bool,
    battery: Option<u8>,
}

impl SensorState {
    const fn new() -> Self {
        Self { connected: false, battery: None }
    }
}

static SENSOR_STATE: Mutex<CriticalSectionRawMutex, SensorState> = Mutex::new(SensorState::new());

pub async fn run(stack: &Stack<'_, super::MyController, DefaultPacketPool>) {
    static SERVER: StaticCell<BikeServer<'static>> = StaticCell::new();
    let server = SERVER.init(
        BikeServer::new_with_config(GapConfig::Peripheral(PeripheralConfig {
            name: "Voop",
            appearance: &appearance::cycling::SPEED_AND_CADENCE_SENSOR,
        }))
        .expect("BikeServer init failed"),
    );

    join(
        // DataPoint creation + sensor state tracking (runs forever).
        async {
            let Some(mut crank_rx) = crate::ble::central::CRANK_REVS.receiver() else {
                log::error!("[BLE peripheral] CRANK_REVS: no free receiver slot");
                return;
            };
            let Some(mut gps_rx) = crate::gps::GPS.receiver() else {
                log::error!("[BLE peripheral] GPS: no free receiver slot");
                return;
            };
            let Some(mut sensor_conn_rx) = crate::ble::central::SENSOR_CONNECTED.receiver() else {
                log::error!("[BLE peripheral] SENSOR_CONNECTED: no free receiver slot");
                return;
            };
            let Some(mut sensor_bat_rx) = crate::ble::central::SENSOR_BATTERY.receiver() else {
                log::error!("[BLE peripheral] SENSOR_BATTERY: no free receiver slot");
                return;
            };

            let mut current_lat: Option<i32> = None;
            let mut current_lon: Option<i32> = None;

            loop {
                match select4(
                    crank_rx.changed(),
                    gps_rx.changed(),
                    sensor_conn_rx.changed(),
                    sensor_bat_rx.changed(),
                )
                .await
                {
                    Either4::First(revs) => {
                        let time = crate::clock::now().await;
                        let point = DataPoint {
                            time,
                            crank_revs: Some(revs),
                            lat_microdeg: current_lat,
                            lon_microdeg: current_lon,
                        };
                        STORE.lock().await.push(point);
                        LIVE.signal(point);
                    }
                    Either4::Second(gps) => {
                        current_lat = Some(gps.lat_microdeg);
                        current_lon = Some(gps.lon_microdeg);
                    }
                    Either4::Third(connected) => {
                        SENSOR_STATE.lock().await.connected = connected;
                    }
                    Either4::Fourth(bat) => {
                        SENSOR_STATE.lock().await.battery = Some(bat);
                    }
                }
            }
        },
        // iOS connection lifecycle (runs forever: advertise → connect → stream → repeat).
        async {
            loop {
                log::info!("[BLE peripheral] Advertising...");

                let mut peripheral = stack.peripheral();
                let sets = [AdvertisementSet {
                    params: AdvertisementParameters::default(),
                    data: Advertisement::ExtConnectableNonscannableUndirected { adv_data: ADV_DATA },
                    address: None,
                }];
                let mut handles = AdvertisementSet::handles(&sets);
                let advertiser = match peripheral.advertise_ext(&sets, &mut handles).await {
                    Ok(a) => a,
                    Err(e) => {
                        log::warn!("[BLE peripheral] advertise error: {:?}", e);
                        continue;
                    }
                };

                log::info!("[BLE peripheral] Waiting for connection...");
                let conn = match with_timeout(Duration::from_secs(10), advertiser.accept()).await {
                    Err(_) => {
                        log::warn!("[BLE peripheral] accept timed out");
                        continue;
                    }
                    Ok(Ok(c)) => c,
                    Ok(Err(e)) => {
                        log::warn!("[BLE peripheral] accept error: {:?}", e);
                        continue;
                    }
                };

                log::info!("[BLE peripheral] iOS connected");

                let gatt_conn = match conn.with_attribute_server(&server.server) {
                    Ok(gc) => gc,
                    Err(e) => {
                        log::warn!("[BLE peripheral] GATT setup error: {:?}", e);
                        continue;
                    }
                };

                // Snapshot current sensor state for the STATUS characteristic.
                let status = {
                    let ss = SENSOR_STATE.lock().await;
                    DeviceStatus {
                        mcu_battery: BatteryStatus { percent: 100, state: BatteryState::Charging },
                        sensor_connected: ss.connected,
                        sensor_battery: ss.battery,
                    }
                };
                gatt_conn.set(&server.bike.status, &status.pack()).ok();

                IOS_CONNECTED.sender().send(true);

                let stream_handle = server.bike.stream.handle;
                let time_sync_handle = server.bike.time_sync.handle;

                join(
                    // Drain GATT events + push status updates every second.
                    // Uses Characteristic::notify(&gatt_conn, ...) which targets this specific
                    // connection directly, bypassing the CCCD peer-identity lookup in
                    // AttributeServer::notify(stack, ...) that silently no-ops when the CCCD
                    // table entry isn't found for the connection.
                    async {
                        let mut ticker = Ticker::every(Duration::from_secs(1));
                        loop {
                            match select(gatt_conn.next(), ticker.next()).await {
                                Either::First(GattConnectionEvent::Disconnected { .. }) => break,
                                Either::First(GattConnectionEvent::Gatt { event }) => {
                                    match event {
                                        GattEvent::Write(ev)
                                            if ev.handle() == time_sync_handle =>
                                        {
                                            let unix_s = ev.with_data(|_offset, data| {
                                                if data.len() >= 4 {
                                                    Some(u32::from_le_bytes([
                                                        data[0], data[1], data[2], data[3],
                                                    ]))
                                                } else {
                                                    None
                                                }
                                            });
                                            ev.accept().ok();
                                            if let Some(t) = unix_s {
                                                log::info!(
                                                    "[BLE peripheral] Time sync: {}",
                                                    t
                                                );
                                                crate::clock::set(t).await;
                                            }
                                        }
                                        _ => {
                                            event.accept().ok();
                                        }
                                    }
                                }
                                Either::First(_) => {}
                                Either::Second(()) => {
                                    let status = {
                                        let ss = SENSOR_STATE.lock().await;
                                        DeviceStatus {
                                            mcu_battery: BatteryStatus {
                                                percent: 100,
                                                state: BatteryState::Charging,
                                            },
                                            sensor_connected: ss.connected,
                                            sensor_battery: ss.battery,
                                        }
                                    };
                                    let packed = status.pack();
                                    // store=true updates the readable attribute value too.
                                    let _ = server
                                        .bike
                                        .status
                                        .notify(&gatt_conn, &packed, true)
                                        .await;
                                }
                            }
                        }
                    },
                    // Replay buffered points, then stream live.
                    async {
                        log::info!("[BLE peripheral] Replaying buffered points...");
                        loop {
                            let point = STORE.lock().await.pop_newest();
                            match point {
                                None => break,
                                Some(p) => {
                                    let packed = p.pack();
                                    if server
                                        .notify(stack, stream_handle, &packed[..])
                                        .await
                                        .is_err()
                                    {
                                        log::warn!(
                                            "[BLE peripheral] notify error during replay"
                                        );
                                        return;
                                    }
                                }
                            }
                        }

                        // Discard any DataPoints that arrived during replay — they're in the
                        // buffer and would be replayed on next connect anyway.
                        LIVE.reset();

                        log::info!("[BLE peripheral] Streaming live...");
                        loop {
                            let point = LIVE.wait().await;
                            let packed = point.pack();
                            if server
                                .notify(stack, stream_handle, &packed[..])
                                .await
                                .is_err()
                            {
                                log::warn!(
                                    "[BLE peripheral] notify error during live stream"
                                );
                                return;
                            }
                        }
                    },
                )
                .await;

                log::info!("[BLE peripheral] iOS disconnected");
                IOS_CONNECTED.sender().send(false);
            }
        },
    )
    .await;
}
