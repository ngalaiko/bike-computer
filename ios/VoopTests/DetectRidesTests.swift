import Foundation
import Testing
@testable import Voop

struct DetectRidesTests {
    /// A point timed by GPS unix seconds, so `absoluteDate` is deterministic (independent of
    /// `receivedAt`) and the gap arithmetic is exact.
    private func point(unix: UInt32, revs: UInt16? = nil) -> RawPoint {
        RawPoint(from: DataPoint(time: .unix(seconds: unix), latMicrodeg: nil, lonMicrodeg: nil, crankRevs: revs))
    }

    @Test func splitsSegmentsOnGapLongerThanThreshold() {
        let points = [
            point(unix: 1000, revs: 0),
            point(unix: 1001, revs: 5),
            // 99 s gap > 60 s threshold → new segment
            point(unix: 1100, revs: 0),
            point(unix: 1101, revs: 5),
        ]
        let rides = DetectRides.detect(points: points, gapThreshold: 60)
        #expect(rides.count == 2)
        #expect(rides[0].startDate == Date(timeIntervalSince1970: 1000))
        #expect(rides[1].startDate == Date(timeIntervalSince1970: 1100))
    }

    @Test func keepsContiguousPointsInOneRide() {
        let points = (0 ..< 5).map { point(unix: 1000 + UInt32($0), revs: UInt16($0)) }
        let rides = DetectRides.detect(points: points, gapThreshold: 60)
        #expect(rides.count == 1)
        #expect(rides[0].points.count == 5)
    }

    @Test func dropsSinglePointSegments() {
        let points = [
            point(unix: 1000, revs: 0),
            point(unix: 1001, revs: 5),
            point(unix: 2000, revs: 0), // isolated by a big gap → segment of 1, dropped
        ]
        let rides = DetectRides.detect(points: points, gapThreshold: 60)
        #expect(rides.count == 1)
    }

    @Test func emptyOrSingleInputProducesNoRides() {
        #expect(DetectRides.detect(points: [], gapThreshold: 60).isEmpty)
        #expect(DetectRides.detect(points: [point(unix: 1000)], gapThreshold: 60).isEmpty)
    }

    @Test func absoluteDateUsesUnixTimeWhenPresent() {
        #expect(DetectRides.absoluteDate(for: point(unix: 1_234_567)) == Date(timeIntervalSince1970: 1_234_567))
    }
}
