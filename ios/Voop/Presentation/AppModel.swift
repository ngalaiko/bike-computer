import CoreLocation
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    let ble: BLEManager
    let health: HealthKitService
    let pointStore: PointStore
    let settings: AppSettings
    let activityController = RideActivityController()

    private(set) var detectedRides: [Ride] = []
    private(set) var isDevicePaired: Bool = UserDefaults.standard.bool(forKey: "isDevicePaired")
    private(set) var currentRpm: Int = 0
    private(set) var currentLocation: CLLocationCoordinate2D?

    /// When a cadence reading last arrived. The sensor's battery/status report is
    /// infrequent, so this is the reliable signal that the sensor is actually live.
    private(set) var lastCadenceDate: Date?

    private var lastCrankPoint: (revs: UInt16, date: Date)?

    init() {
        ble = BLEManager()
        health = HealthKitService()
        pointStore = (try? PointStore()) ?? { fatalError("Failed to create PointStore") }()
        settings = AppSettings()
        redetect()
    }

    func markDevicePaired() {
        isDevicePaired = true
        UserDefaults.standard.set(true, forKey: "isDevicePaired")
    }

    func startReceiving() async {
        for await point in ble.dataPoints {
            if let revs = point.crankRevs {
                let now = Date.now
                if let last = lastCrankPoint {
                    let dt = now.timeIntervalSince(last.date)
                    let delta = Int32(revs) - Int32(last.revs)
                    if dt > 0 && delta > 0 {
                        currentRpm = Int((Double(delta) / dt * 60.0).rounded())
                    }
                }
                lastCrankPoint = (revs: revs, date: now)
                lastCadenceDate = now
            }
            if let lat = point.latMicrodeg, let lon = point.lonMicrodeg {
                currentLocation = CLLocationCoordinate2D(
                    latitude: Double(lat) / 1_000_000.0,
                    longitude: Double(lon) / 1_000_000.0
                )
            }
            try? pointStore.insert(point)
            redetect()
            await reconcileActivity()
        }
    }

    /// The ride currently in progress: the most recent segment, if the stop-pause gap since its
    /// last point hasn't elapsed yet. Shared by the live card (`MainView`) and the Live Activity.
    func ongoingRide(at now: Date = .now) -> Ride? {
        guard let last = detectedRides.last,
              now.timeIntervalSince(last.endDate) < settings.gapThreshold
        else { return nil }
        return last
    }

    /// Drives the Live Activity to match the ongoing ride (or ends it when none is in progress).
    func reconcileActivity(at now: Date = .now) async {
        guard let ride = ongoingRide(at: now) else {
            await activityController.reconcile(rideStartDate: nil, rideEndDate: nil, state: nil)
            return
        }
        let config = CalculateMetrics.Config(
            gearRatio: settings.gearRatio,
            wheelCircumferenceMeters: settings.wheelCircumferenceMeters
        )
        let distance = CalculateMetrics.cadenceDistance(points: ride.points, config: config)
        // Current speed from the live cadence, using the same gear/wheel formula as `samples`.
        let speedKph = Double(currentRpm) / 60.0 * config.gearRatio * config.wheelCircumferenceMeters * 3.6
        let state = RideActivityAttributes.ContentState(
            distanceMeters: distance,
            currentSpeedKph: speedKph,
            currentCadenceRpm: currentRpm,
            elapsedInterval: ride.startDate ... .distantFuture,
            isFinished: false
        )
        await activityController.reconcile(rideStartDate: ride.startDate, rideEndDate: ride.endDate, state: state)
    }

    /// Wall-clock loop that keeps the Live Activity honest. The data stream can't detect a ride
    /// *ending* (points stop arriving when the rider stops), so this periodic tick is what ends it.
    func runActivityHeartbeat() async {
        activityController.adoptExisting()
        while !Task.isCancelled {
            await reconcileActivity()
            try? await Task.sleep(for: .seconds(3))
        }
        await activityController.end()
    }

    /// Every stored raw point as CSV, including the absolute date used for detection.
    func exportCSV() -> String {
        let points = (try? pointStore.fetchAll()) ?? []
        var lines = ["index,receivedAt,absoluteDate,unixSeconds,monotonicMs,latMicrodeg,lonMicrodeg,crankRevs"]
        for (index, p) in points.enumerated() {
            let absolute = DetectRides.absoluteDate(for: p).ISO8601Format()
            let columns: [String] = [
                String(index),
                p.receivedAt.ISO8601Format(),
                absolute,
                p.unixSeconds.map(String.init) ?? "",
                p.monotonicMs.map(String.init) ?? "",
                p.latMicrodeg.map(String.init) ?? "",
                p.lonMicrodeg.map(String.init) ?? "",
                p.crankRevs.map(String.init) ?? "",
            ]
            lines.append(columns.joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    /// Writes the CSV export to a temporary file and returns its URL for sharing.
    func writeCSVExport() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "voop-export.csv")
        try exportCSV().write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Removes the raw points that make up a ride, then re-derives the ride list.
    func deleteRide(_ ride: Ride) {
        let all = (try? pointStore.fetchAll()) ?? []
        let toDelete = all.filter { raw in
            let date = DetectRides.absoluteDate(for: raw)
            return date >= ride.startDate && date <= ride.endDate
        }
        try? pointStore.delete(toDelete)
        redetect()
    }

    private func redetect() {
        let points = (try? pointStore.fetchAll()) ?? []
        detectedRides = DetectRides.detect(points: points, gapThreshold: settings.gapThreshold)
    }
}
