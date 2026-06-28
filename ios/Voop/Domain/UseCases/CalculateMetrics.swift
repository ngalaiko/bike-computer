import CoreLocation
import Foundation

struct RideMetrics {
    let totalDistanceMeters: Double
    let durationSeconds: TimeInterval
    let averageSpeedKph: Double
    let maxSpeedKph: Double
    let averageCadenceRpm: Double
    let maxCadenceRpm: Double
}

/// One moment in a ride's time series: where you were, and how fast you were going
/// and pedaling. `elapsed` is seconds since the ride started. This is the single
/// source that feeds the route gradient, the speed/cadence chart, and per-km splits.
struct RideSample: Identifiable {
    let id: Int
    let elapsed: TimeInterval
    let coordinate: CLLocationCoordinate2D?
    let speedKph: Double
    let cadenceRpm: Double
}

enum CalculateMetrics {
    /// Gear ratio × wheel circumference in meters, used to convert crank revs to distance.
    /// Defaults: 46/16 chainring, 700×25c wheel (2.105 m circumference).
    struct Config {
        var gearRatio: Double = 46.0 / 16.0
        var wheelCircumferenceMeters: Double = 2.105
    }

    /// Distance derived from crank revolutions, gear ratio, and wheel circumference.
    /// Sums forward crank-rev deltas to ignore counter resets/wraps.
    static func cadenceDistance(points: [TimestampedPoint], config: Config = .init()) -> Double {
        guard points.count >= 2 else { return 0 }
        var total = 0.0
        for i in 1 ..< points.count {
            let revDelta = Int32(points[i].cumulativeCrankRevs) - Int32(points[i - 1].cumulativeCrankRevs)
            if revDelta > 0 {
                total += Double(revDelta) * config.gearRatio * config.wheelCircumferenceMeters
            }
        }
        return total
    }

    static func compute(ride: Ride, config: Config = .init()) -> RideMetrics {
        let series = samples(ride: ride, config: config)
        // Averages count only intervals where the crank actually advanced (a coast
        // reads as 0); maxes scan the whole series. This preserves the original
        // behavior while keeping `samples` the one place the speed formula lives.
        let moving = series.filter { $0.cadenceRpm > 0 }
        func mean(_ values: [Double]) -> Double {
            values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
        }

        return RideMetrics(
            totalDistanceMeters: cadenceDistance(points: ride.points, config: config),
            durationSeconds: ride.duration,
            averageSpeedKph: mean(moving.map(\.speedKph)),
            maxSpeedKph: series.map(\.speedKph).max() ?? 0,
            averageCadenceRpm: mean(moving.map(\.cadenceRpm)),
            maxCadenceRpm: series.map(\.cadenceRpm).max() ?? 0
        )
    }

    /// Per-point time series of speed and cadence, derived the same way as the metrics
    /// (crank-rev deltas → distance → speed). Index 0 is the ride start with no motion
    /// yet; each later sample covers the interval ending at that point. Intervals with
    /// no crank advance read as 0 — a coast — which keeps the chart continuous and honest.
    static func samples(ride: Ride, config: Config = .init()) -> [RideSample] {
        let points = ride.points
        guard let start = points.first?.date else { return [] }

        var result: [RideSample] = [
            RideSample(id: 0, elapsed: 0, coordinate: points[0].coordinate, speedKph: 0, cadenceRpm: 0),
        ]

        for i in 1 ..< points.count {
            let dt = points[i].date.timeIntervalSince(points[i - 1].date)
            var speedKph = 0.0
            var cadenceRpm = 0.0
            if dt > 0 {
                let revDelta = Int32(points[i].cumulativeCrankRevs) - Int32(points[i - 1].cumulativeCrankRevs)
                if revDelta > 0 {
                    cadenceRpm = Double(revDelta) / dt * 60.0
                    let distanceM = Double(revDelta) * config.gearRatio * config.wheelCircumferenceMeters
                    speedKph = (distanceM / dt) * 3.6
                }
            }
            result.append(RideSample(
                id: i,
                elapsed: points[i].date.timeIntervalSince(start),
                coordinate: points[i].coordinate,
                speedKph: speedKph,
                cadenceRpm: cadenceRpm
            ))
        }
        return result
    }
}
