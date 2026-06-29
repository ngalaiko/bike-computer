import Charts
import MapKit
import SwiftUI

struct RideDetailView: View {
    let ride: Ride
    @Environment(AppModel.self) private var appModel
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirm = false

    /// Scrub position, shared by the chart and the map marker. Seconds since ride start.
    @State private var selectedElapsed: Double?

    private var metricsConfig: CalculateMetrics.Config {
        .init(gearRatio: settings.gearRatio, wheelCircumferenceMeters: settings.wheelCircumferenceMeters)
    }

    var body: some View {
        // Derived once per render and shared by the map, the chart, splits, and stats.
        let samples = CalculateMetrics.samples(ride: ride, config: metricsConfig)
        let speedRange = Self.speedRange(for: samples)
        let segments = Self.routeSegments(from: samples)
        let metrics = CalculateMetrics.compute(ride: ride, config: metricsConfig)
        let selectedSample = selectedElapsed.flatMap { Self.sample(nearestTo: $0, in: samples) }
        let speedPoints = Self.speedPoints(from: samples)

        List {
            Section("Summary") {
                VStack(spacing: 10) {
                    // When the ride ran, then the two numbers that carry the screen.
                    Text(ride.clockRange)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 0) {
                        HeroStat(
                            value: Measurement(value: metrics.totalDistanceMeters, unit: UnitLength.meters)
                                .formatted(.measurement(width: .abbreviated, usage: .road)),
                            label: "Distance"
                        )
                        Divider()
                        HeroStat(
                            value: Duration.seconds(ride.duration).formatted(.time(pattern: .hourMinute)),
                            label: "Duration"
                        )
                    }
                }
                .padding(.vertical, 4)

                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    alignment: .center
                ) {
                    StatTile(value: "\(Int(metrics.averageSpeedKph)) km/h", label: "Avg Speed")
                    StatTile(value: "\(Int(metrics.maxSpeedKph)) km/h", label: "Max Speed")
                    StatTile(value: "\(Int(metrics.averageCadenceRpm)) rpm", label: "Avg Cadence")
                    StatTile(value: "\(Int(metrics.maxCadenceRpm)) rpm", label: "Max Cadence")
                }
                .padding(.vertical, 4)
            }

            if !segments.isEmpty {
                Section {
                    Map {
                        ForEach(segments) { segment in
                            MapPolyline(coordinates: segment.coordinates)
                                .stroke(
                                    SpeedRamp.color(forSpeed: segment.speedKph, in: speedRange),
                                    lineWidth: 4
                                )
                        }
                        // Marker rides the route as you scrub the chart below.
                        if let coordinate = selectedSample?.coordinate {
                            Annotation("", coordinate: coordinate) {
                                Circle()
                                    .fill(.background)
                                    .frame(width: 14, height: 14)
                                    .overlay(Circle().stroke(Color.accentColor, lineWidth: 3))
                                    .shadow(radius: 2)
                            }
                        }
                    }
                    .frame(height: 260)
                    .overlay(alignment: .bottomTrailing) {
                        SpeedLegend()
                            .padding(10)
                    }
                    .listRowInsets(EdgeInsets())
                }
            }

            if samples.count >= 2 {
                Section("Speed") {
                    SpeedChart(
                        points: speedPoints,
                        selectedElapsed: $selectedElapsed
                    )
                    .frame(height: 170)
                    .listRowSeparator(.hidden)
                }
            }

            Section {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Delete Ride", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle(ride.startDate.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Delete this ride?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Ride", role: .destructive) {
                appModel.deleteRide(ride)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes the ride's recorded points.")
        }
    }

    // MARK: - Derived data

    /// The ride's own speed span, used to normalize colors. Falls back to a 0…1 range
    /// when there's no spread (e.g. a ride with no cadence data), so coloring still works.
    private static func speedRange(for samples: [RideSample]) -> ClosedRange<Double> {
        let speeds = samples.map(\.speedKph)
        let lo = speeds.min() ?? 0
        let hi = speeds.max() ?? 0
        return hi > lo ? lo ... hi : 0 ... max(hi, 1)
    }

    /// One short polyline per interval, between consecutive points that both have a fix,
    /// carrying that interval's speed so the line can be colored segment by segment.
    private static func routeSegments(from samples: [RideSample]) -> [RouteSegment] {
        guard samples.count >= 2 else { return [] }
        var segments: [RouteSegment] = []
        for i in 1 ..< samples.count {
            guard let from = samples[i - 1].coordinate, let to = samples[i].coordinate else { continue }
            segments.append(RouteSegment(id: i, coordinates: [from, to], speedKph: samples[i].speedKph))
        }
        return segments
    }

    /// The sample closest in time to a scrub position.
    private static func sample(nearestTo elapsed: Double, in samples: [RideSample]) -> RideSample? {
        samples.min(by: { abs($0.elapsed - elapsed) < abs($1.elapsed - elapsed) })
    }

    /// Chart points with speed run through a centered moving average. Cadence-derived
    /// speed quantizes hard at low cadence (a crank rev either lands in a given second
    /// or it doesn't), so the raw series is a picket fence; averaging a window around
    /// each point recovers the trend the rider actually feels.
    private static func speedPoints(from samples: [RideSample], window: Int = 11) -> [SpeedPoint] {
        let speeds = samples.map(\.speedKph)
        let half = max(window / 2, 1)
        return samples.indices.map { i in
            let lo = max(0, i - half)
            let hi = min(speeds.count - 1, i + half)
            let mean = speeds[lo ... hi].reduce(0, +) / Double(hi - lo + 1)
            return SpeedPoint(id: i, elapsed: samples[i].elapsed, kph: mean)
        }
    }
}

// MARK: - Chart

private struct SpeedPoint: Identifiable {
    let id: Int
    let elapsed: TimeInterval
    let kph: Double
}

/// Speed over time, with a draggable cursor that publishes its position so the route
/// map can show where you were. Uses `chartXSelection` for the scrub gesture. (Cadence
/// is omitted: on a fixed gear it's just speed in different units — the same curve.)
private struct SpeedChart: View {
    let points: [SpeedPoint]
    @Binding var selectedElapsed: Double?

    private var selected: SpeedPoint? {
        guard let elapsed = selectedElapsed else { return nil }
        return points.min(by: { abs($0.elapsed - elapsed) < abs($1.elapsed - elapsed) })
    }

    var body: some View {
        Chart {
            ForEach(points) { point in
                AreaMark(
                    x: .value("Time", point.elapsed),
                    y: .value("Speed", point.kph)
                )
                .foregroundStyle(
                    .linearGradient(
                        colors: [Color.accentColor.opacity(0.28), Color.accentColor.opacity(0.02)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Time", point.elapsed),
                    y: .value("Speed", point.kph)
                )
                .foregroundStyle(Color.accentColor)
                .interpolationMethod(.catmullRom)
            }

            if let selected {
                RuleMark(x: .value("Time", selected.elapsed))
                    .foregroundStyle(.secondary.opacity(0.4))

                // Pill follows the moving dot and stays inside the plot, so it never
                // rides up against the "Speed" header above the chart.
                PointMark(
                    x: .value("Time", selected.elapsed),
                    y: .value("Speed", selected.kph)
                )
                .foregroundStyle(Color.accentColor)
                .annotation(
                    position: .top,
                    spacing: 6,
                    overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .plot))
                ) {
                    Text("\(Int(selected.kph)) km/h")
                        .font(.caption2.bold().monospacedDigit())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.thinMaterial, in: Capsule())
                }
            }
        }
        .chartXSelection(value: $selectedElapsed)
        .chartXAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let seconds = value.as(Double.self) {
                        Text(Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond)))
                    }
                }
            }
        }
    }
}

// MARK: - Route + color

/// A stretch of route drawn as its own polyline so it can take its own color.
private struct RouteSegment: Identifiable {
    let id: Int
    let coordinates: [CLLocationCoordinate2D]
    let speedKph: Double
}

/// Maps a speed onto a cool→warm ramp (slow blue → fast red) — the route-coloring
/// convention shared by Apple Fitness, Garmin, and Komoot. Stops match the design doc.
enum SpeedRamp {
    private static let stops: [(at: Double, color: Color)] = [
        (0.00, Color(red: 0.145, green: 0.388, blue: 0.659)), // #2563A8  slow
        (0.40, Color(red: 0.180, green: 0.620, blue: 0.561)), // #2E9E8F
        (0.72, Color(red: 0.878, green: 0.659, blue: 0.180)), // #E0A82E
        (1.00, Color(red: 0.824, green: 0.271, blue: 0.184)), // #D2452F  fast
    ]

    /// Color at a normalized position 0…1 along the ramp, interpolating between stops.
    static func color(at t: Double) -> Color {
        let clamped = min(max(t, 0), 1)
        for i in 1 ..< stops.count where clamped <= stops[i].at {
            let lower = stops[i - 1]
            let upper = stops[i]
            let span = upper.at - lower.at
            let fraction = span > 0 ? (clamped - lower.at) / span : 0
            return lower.color.mix(with: upper.color, by: fraction)
        }
        return stops.last!.color
    }

    static func color(forSpeed speed: Double, in range: ClosedRange<Double>) -> Color {
        let span = range.upperBound - range.lowerBound
        let t = span > 0 ? (speed - range.lowerBound) / span : 0
        return color(at: t)
    }

    /// The full ramp as a horizontal gradient, for the legend swatch.
    static var gradient: LinearGradient {
        LinearGradient(colors: stops.map(\.color), startPoint: .leading, endPoint: .trailing)
    }
}

/// The thing every app that color-codes a route forgets to ship.
private struct SpeedLegend: View {
    var body: some View {
        HStack(spacing: 6) {
            Text("slow")
            Capsule()
                .fill(SpeedRamp.gradient)
                .frame(width: 44, height: 6)
            Text("fast")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.thinMaterial, in: Capsule())
    }
}

// MARK: - Stat tiles

private struct HeroStat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title.bold().monospacedDigit())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

private struct StatTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.bold().monospacedDigit())
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }
}
