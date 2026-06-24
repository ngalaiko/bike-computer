import Foundation
import SwiftData

@Model
final class RawPoint {
    var receivedAt: Date
    var unixSeconds: Int?
    var monotonicMs: Int?
    var latMicrodeg: Int32?
    var lonMicrodeg: Int32?
    var crankRevs: Int32?

    init(from point: DataPoint, receivedAt: Date = .now) {
        self.receivedAt = receivedAt
        switch point.time {
        case .unix(let s): self.unixSeconds = Int(s)
        case .monotonic(let ms): self.monotonicMs = Int(ms)
        }
        self.latMicrodeg = point.latMicrodeg
        self.lonMicrodeg = point.lonMicrodeg
        self.crankRevs = point.crankRevs.map { Int32($0) }
    }

    var dataPoint: DataPoint {
        let time: Time
        if let s = unixSeconds {
            time = .unix(seconds: UInt32(s))
        } else if let ms = monotonicMs {
            time = .monotonic(ms: UInt32(ms))
        } else {
            time = .monotonic(ms: 0)
        }
        return DataPoint(
            time: time,
            latMicrodeg: latMicrodeg,
            lonMicrodeg: lonMicrodeg,
            crankRevs: crankRevs.map { UInt16(clamping: $0) }
        )
    }
}
