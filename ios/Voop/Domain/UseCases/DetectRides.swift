import CoreLocation
import Foundation

typealias TimeAnchor = (iosDate: Date, unixSeconds: UInt32)

enum DetectRides {
    static let gapThreshold: TimeInterval = 5 * 60
    static let minimumDistanceMeters: Double = 500

    static func detect(points: [RawPoint], anchor: TimeAnchor?) -> [Ride] {
        guard points.count >= 2 else { return [] }

        var segments: [[RawPoint]] = []
        var current: [RawPoint] = [points[0]]
        for point in points.dropFirst() {
            if let gap = elapsed(from: current.last!, to: point, anchor: anchor), gap > gapThreshold {
                segments.append(current)
                current = [point]
            } else {
                current.append(point)
            }
        }
        segments.append(current)

        return segments.enumerated().compactMap { index, segment in
            let isLast = index == segments.count - 1
            guard segment.count >= 2 else { return nil }

            let timestamped: [TimestampedPoint] = segment.compactMap { raw in
                guard let date = absoluteDate(for: raw, anchor: anchor) else { return nil }
                let p = raw.dataPoint
                let coord = p.latMicrodeg.flatMap { lat in
                    p.lonMicrodeg.map { lon in
                        CLLocationCoordinate2D(
                            latitude: Double(lat) / 1_000_000.0,
                            longitude: Double(lon) / 1_000_000.0
                        )
                    }
                }
                return TimestampedPoint(date: date, coordinate: coord, cumulativeCrankRevs: p.crankRevs ?? 0)
            }
            guard !timestamped.isEmpty else { return nil }

            // Apply distance filter to completed segments only; last segment may still be ongoing.
            if !isLast, CalculateMetrics.totalDistance(points: timestamped) < minimumDistanceMeters {
                return nil
            }

            return Ride(
                id: UUID(),
                startDate: timestamped.first!.date,
                endDate: timestamped.last!.date,
                points: timestamped
            )
        }
    }

    private static func elapsed(from a: RawPoint, to b: RawPoint, anchor: TimeAnchor?) -> TimeInterval? {
        guard let da = absoluteDate(for: a, anchor: anchor),
              let db = absoluteDate(for: b, anchor: anchor)
        else { return nil }
        return max(0, db.timeIntervalSince(da))
    }

    private static func absoluteDate(for raw: RawPoint, anchor: TimeAnchor?) -> Date? {
        switch raw.dataPoint.time {
        case .unix(let s):
            return Date(timeIntervalSince1970: TimeInterval(s))
        case .monotonic:
            guard let anchor else { return nil }
            let delta = raw.receivedAt.timeIntervalSince(anchor.iosDate)
            let estimated = TimeInterval(anchor.unixSeconds) + delta
            guard estimated > 0 else { return nil }
            return Date(timeIntervalSince1970: estimated)
        }
    }
}
