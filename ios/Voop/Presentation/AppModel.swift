import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    let ble: BLEManager
    let health: HealthKitService
    let pointStore: PointStore

    private(set) var detectedRides: [Ride] = []
    private(set) var isDevicePaired: Bool = UserDefaults.standard.bool(forKey: "isDevicePaired")

    // Set once when the first unix-timestamped DataPoint arrives.
    // Used to retroactively convert buffered monotonic points to unix time.
    private var timeAnchor: (iosDate: Date, unixSeconds: UInt32)?

    init() {
        ble = BLEManager()
        health = HealthKitService()
        pointStore = (try? PointStore()) ?? { fatalError("Failed to create PointStore") }()
        redetect()
    }

    func markDevicePaired() {
        isDevicePaired = true
        UserDefaults.standard.set(true, forKey: "isDevicePaired")
    }

    func startReceiving() async {
        for await point in ble.dataPoints {
            if timeAnchor == nil, case .unix(let seconds) = point.time {
                timeAnchor = (iosDate: Date.now, unixSeconds: seconds)
            }
            try? pointStore.insert(point)
            redetect()
        }
    }

    private func redetect() {
        let points = (try? pointStore.fetchAll()) ?? []
        detectedRides = DetectRides.detect(points: points, anchor: timeAnchor)
    }
}
