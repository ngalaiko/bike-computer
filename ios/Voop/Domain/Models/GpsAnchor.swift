import Foundation

/// Links MCU monotonic time to wall clock time.
/// Set once on the first valid GPS fix; used to reconstruct absolute timestamps.
struct GpsAnchor {
    let monotonicMs: UInt32
    let wallClockDate: Date

    func date(forMonotonicMs ms: UInt32) -> Date {
        let offsetSeconds = Double(Int64(ms) - Int64(monotonicMs)) / 1000.0
        return wallClockDate.addingTimeInterval(offsetSeconds)
    }
}
