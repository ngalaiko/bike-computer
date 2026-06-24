import MapKit
import SwiftUI

struct RideDetailView: View {
    let ride: Ride
    private var metrics: RideMetrics {
        CalculateMetrics.compute(ride: ride)
    }

    var body: some View {
        List {
            Section {
                Map {
                    MapPolyline(coordinates: ride.points.compactMap {
                        $0.coordinate.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
                    })
                    .stroke(.blue, lineWidth: 3)
                }
                .frame(height: 260)
                .listRowInsets(EdgeInsets())
            }

            Section("Summary") {
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    alignment: .center
                ) {
                    StatTile(
                        value: Duration.seconds(ride.duration).formatted(.time(pattern: .hourMinute)),
                        label: "Duration"
                    )
                    StatTile(
                        value: Measurement(value: metrics.totalDistanceMeters, unit: UnitLength.meters)
                            .formatted(.measurement(width: .abbreviated, usage: .road)),
                        label: "Distance"
                    )
                    StatTile(value: "\(Int(metrics.averageSpeedKph)) km/h", label: "Avg Speed")
                    StatTile(value: "\(Int(metrics.maxSpeedKph)) km/h", label: "Max Speed")
                    StatTile(value: "\(Int(metrics.averageCadenceRpm)) rpm", label: "Avg Cadence")
                    StatTile(value: "\(Int(metrics.maxCadenceRpm)) rpm", label: "Max Cadence")
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle(ride.startDate.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct StatTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.bold().monospacedDigit())
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}
