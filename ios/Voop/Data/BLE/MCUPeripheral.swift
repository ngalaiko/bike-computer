@preconcurrency import CoreBluetooth
import Foundation

private nonisolated(unsafe) let mcuServiceUUID = CBUUID(string: serviceUuid())
private nonisolated(unsafe) let dataTransferCharUUID = CBUUID(string: dataCharUuid())

final class MCUPeripheral: NSObject, CBPeripheralDelegate, @unchecked Sendable {
    var onDataPoint: (@MainActor (DataPoint) -> Void)?
    var onStatusUpdate: (@MainActor (DeviceStatus) -> Void)?

    private let peripheral: CBPeripheral

    init(peripheral: CBPeripheral) {
        self.peripheral = peripheral
    }

    func discoverServices() {
        peripheral.discoverServices([mcuServiceUUID])
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices _: (any Error)?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == mcuServiceUUID }) else { return }
        peripheral.discoverCharacteristics([dataTransferCharUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error _: (any Error)?) {
        guard let chars = service.characteristics else { return }
        for char in chars where char.uuid == dataTransferCharUUID {
            peripheral.setNotifyValue(true, for: char)
        }
    }

    func peripheral(
        _: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: (any Error)?
    ) {
        guard error == nil, let data = characteristic.value else { return }
        if characteristic.uuid == dataTransferCharUUID {
            if let point = unpackDataPoint(bytes: data) {
                let cb = onDataPoint
                Task { @MainActor in cb?(point) }
            }
        }
    }
}
