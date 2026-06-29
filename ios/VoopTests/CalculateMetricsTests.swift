import CoreLocation
import Testing
@testable import Voop

struct CalculateMetricsTests {
    /// 1 rev = 2 × 2 = 4 m of travel, chosen so the arithmetic is checkable by hand.
    private let config = CalculateMetrics.Config(gearRatio: 2, wheelCircumferenceMeters: 2)
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func point(_ secondsIn: TimeInterval, revs: UInt16) -> TimestampedPoint {
        TimestampedPoint(date: start.addingTimeInterval(secondsIn), coordinate: nil, cumulativeCrankRevs: revs)
    }

    @Test func distanceSumsForwardRevDeltas() {
        let points = [point(0, revs: 0), point(1, revs: 10), point(2, revs: 20)]
        // 20 revs × 4 m = 80 m
        #expect(CalculateMetrics.cadenceDistance(points: points, config: config) == 80)
    }

    @Test func distanceIgnoresCounterWrapAndResets() {
        // A backward delta (16-bit counter wrap or sensor reset) must contribute nothing.
        let points = [point(0, revs: 65000), point(1, revs: 100)]
        #expect(CalculateMetrics.cadenceDistance(points: points, config: config) == 0)
    }

    @Test func distanceIsZeroBelowTwoPoints() {
        #expect(CalculateMetrics.cadenceDistance(points: [point(0, revs: 5)], config: config) == 0)
        #expect(CalculateMetrics.cadenceDistance(points: [], config: config) == 0)
    }

    @Test func samplesStartAtRestThenComputeSpeed() {
        let ride = Ride(
            startDate: start,
            endDate: start.addingTimeInterval(2),
            points: [point(0, revs: 0), point(1, revs: 10), point(2, revs: 10)]
        )
        let samples = CalculateMetrics.samples(ride: ride, config: config)
        #expect(samples.count == 3)
        // Index 0 is the ride start — no motion yet.
        #expect(samples[0].speedKph == 0)
        #expect(samples[0].cadenceRpm == 0)
        // 10 revs in 1 s → 600 rpm; 40 m in 1 s → 144 km/h with this config.
        #expect(samples[1].cadenceRpm == 600)
        #expect(abs(samples[1].speedKph - 144) < 0.0001)
        // Coasting interval (no rev advance) reads as 0.
        #expect(samples[2].speedKph == 0)
        #expect(samples[2].cadenceRpm == 0)
    }

    @Test func computeAveragesCountOnlyMovingIntervals() {
        let ride = Ride(
            startDate: start,
            endDate: start.addingTimeInterval(2),
            points: [point(0, revs: 0), point(1, revs: 10), point(2, revs: 10)]
        )
        let metrics = CalculateMetrics.compute(ride: ride, config: config)
        #expect(metrics.totalDistanceMeters == 40) // one 10-rev interval × 4 m
        // The coast (0 rpm) is excluded from averages but still seen by the maxes.
        #expect(metrics.averageCadenceRpm == 600)
        #expect(metrics.maxCadenceRpm == 600)
        #expect(abs(metrics.averageSpeedKph - 144) < 0.0001)
        #expect(abs(metrics.maxSpeedKph - 144) < 0.0001)
    }
}
