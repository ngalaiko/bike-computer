import Foundation
import SwiftData

@Model
final class RawPoint {
    var receivedAt: Date
    /// Raw MCU monotonic clock at capture (ms since boot) — always present. The timing spine.
    var uptimeMs: Int
    /// Device's wall-clock estimate when it had an anchor; nil for pre-sync points.
    var unixMillis: Int?
    var latMicrodeg: Int32?
    var lonMicrodeg: Int32?
    var crankRevs: Int
    /// CSC last-crank-event time, 1/1024 s (wraps every 64 s).
    var crankEventTime: Int

    init(from point: DataPoint, receivedAt: Date = .now) {
        self.receivedAt = receivedAt
        uptimeMs = Int(point.uptimeMs)
        unixMillis = point.unixMillis.map { Int($0) }
        latMicrodeg = point.latMicrodeg
        lonMicrodeg = point.lonMicrodeg
        crankRevs = Int(point.crankRevs)
        crankEventTime = Int(point.crankEventTime)
    }

    var dataPoint: DataPoint {
        DataPoint(
            uptimeMs: UInt32(clamping: uptimeMs),
            unixMillis: unixMillis.map { UInt64($0) },
            latMicrodeg: latMicrodeg,
            lonMicrodeg: lonMicrodeg,
            crankRevs: UInt16(clamping: crankRevs),
            crankEventTime: UInt16(clamping: crankEventTime)
        )
    }
}
