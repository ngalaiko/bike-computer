import Foundation

protocol DeviceRepository: Sendable {
    var status: DeviceStatus? { get }
    var dataPoints: AsyncStream<DataPoint> { get }
    func startScan() async
    func stopScan() async
}
