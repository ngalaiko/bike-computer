@preconcurrency import CoreBluetooth
import Foundation
import Observation

private nonisolated(unsafe) let mcuServiceUUID = CBUUID(string: serviceUuid())

@MainActor
@Observable
final class BLEManager: NSObject {
    private(set) var connectionState: ConnectionState = .idle
    private(set) var deviceStatus: DeviceStatus?

    private var central: CBCentralManager?
    private var peripheral: MCUPeripheral?
    private var connectingPeripheral: CBPeripheral?

    private var dataPointContinuation: AsyncStream<DataPoint>.Continuation?
    private(set) var dataPoints: AsyncStream<DataPoint>

    enum ConnectionState: Equatable {
        case idle, scanning, connecting, connected, disconnected(Error?)

        static func == (lhs: ConnectionState, rhs: ConnectionState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.scanning, .scanning), (.connecting, .connecting), (.connected, .connected),
                 (.disconnected, .disconnected): return true
            default: return false
            }
        }
    }

    override init() {
        var continuation: AsyncStream<DataPoint>.Continuation!
        dataPoints = AsyncStream { continuation = $0 }
        dataPointContinuation = continuation
        super.init()
        central = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [CBCentralManagerOptionRestoreIdentifierKey: "com.voop.central"]
        )
    }

    func startScan() {
        guard central?.state == .poweredOn else { return }
        connectionState = .scanning
        central?.scanForPeripherals(withServices: [mcuServiceUUID], options: nil)
    }

    func stopScan() {
        central?.stopScan()
        connectionState = .idle
    }
}

extension BLEManager: CBCentralManagerDelegate {
    nonisolated func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        MainActor.assumeIsolated {
            // iOS hands back any peripheral it was managing on our behalf while we were suspended.
            // Re-adopt it so we skip scanning and go straight to the connected state.
            guard let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral],
                  let p = peripherals.first
            else { return }

            connectingPeripheral = p
            central.connect(p, options: nil)
            connectionState = .connecting
        }
    }

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            if central.state == .poweredOn {
                startScan()
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData _: [String: Any],
        rssi _: NSNumber
    ) {
        MainActor.assumeIsolated {
            central.stopScan()
            connectionState = .connecting
            connectingPeripheral = peripheral
            central.connect(peripheral, options: nil)
        }
    }

    nonisolated func centralManager(_: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            connectingPeripheral = nil
            let mcu = MCUPeripheral(peripheral: peripheral)
            mcu.onDataPoint = { [weak self] point in
                self?.dataPointContinuation?.yield(point)
            }
            mcu.onStatusUpdate = { [weak self] status in
                self?.deviceStatus = status
            }
            self.peripheral = mcu
            peripheral.delegate = mcu
            mcu.discoverServices()
            connectionState = .connected
        }
    }

    nonisolated func centralManager(
        _: CBCentralManager,
        didDisconnectPeripheral _: CBPeripheral,
        error: (any Error)?
    ) {
        MainActor.assumeIsolated {
            self.peripheral = nil
            self.connectingPeripheral = nil
            connectionState = .disconnected(error)
            startScan()
        }
    }

    nonisolated func centralManager(
        _: CBCentralManager,
        didFailToConnect _: CBPeripheral,
        error: (any Error)?
    ) {
        MainActor.assumeIsolated {
            connectingPeripheral = nil
            connectionState = .disconnected(error)
            startScan()
        }
    }
}
