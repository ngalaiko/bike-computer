import CoreLocation
import SwiftUI

struct MainView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(AppSettings.self) private var settings
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let ongoing = appModel.ongoingRide(at: ctx.date)
                let completed = completedRides(at: ctx.date)
                List {
                    Section {
                        DeviceStatusRow(
                            connectionState: appModel.ble.connectionState,
                            deviceStatus: appModel.ble.deviceStatus
                        )
                        SensorStatusRow(
                            connectionState: appModel.ble.connectionState,
                            deviceStatus: appModel.ble.deviceStatus,
                            isLive: sensorIsLive(at: ctx.date)
                        )
                    }

                    if case .connected = appModel.ble.connectionState {
                        Section("Current") {
                            CurrentValuesRow(
                                rpm: appModel.currentRpm,
                                location: appModel.currentLocation
                            )
                        }
                    }

                    if let ride = ongoing {
                        Section {
                            RidingRow(ride: ride, now: ctx.date)
                        }
                    }

                    if !completed.isEmpty {
                        Section("Rides") {
                            ForEach(Array(completed.reversed())) { ride in
                                NavigationLink(destination: RideDetailView(ride: ride)) {
                                    CompletedRideRow(ride: ride)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        appModel.deleteRide(ride)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }

                    if ongoing == nil && completed.isEmpty {
                        EmptyRidesView()
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("Voop")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environment(appModel)
                    .environment(settings)
            }
        }
    }

    /// The cadence sensor counts as live if the device reports it connected, or — since
    /// that status/battery report is infrequent — if a cadence reading arrived recently.
    private func sensorIsLive(at now: Date) -> Bool {
        guard case .connected = appModel.ble.connectionState else { return false }
        if appModel.ble.deviceStatus?.sensorConnected == true { return true }
        if let last = appModel.lastCadenceDate, now.timeIntervalSince(last) < 5 { return true }
        return false
    }

    private func completedRides(at now: Date) -> [Ride] {
        var rides = appModel.detectedRides
        if appModel.ongoingRide(at: now) != nil {
            rides = Array(rides.dropLast())
        }
        return rides.filter { DetectRides.qualifies($0, settings: settings) }
    }
}

private struct DeviceStatusRow: View {
    let connectionState: BLEManager.ConnectionState
    let deviceStatus: DeviceStatus?

    var body: some View {
        HStack {
            Text("Device")
            Spacer()
            batteryView
            statusIcon
        }
    }

    @ViewBuilder
    private var batteryView: some View {
        if case .connected = connectionState, let bat = deviceStatus?.mcuBattery {
            HStack(spacing: 3) {
                if bat.state == .charging {
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(.yellow)
                        .font(.caption)
                }
                Text("\(bat.percent)%")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch connectionState {
        case .connected:
            Image(systemName: "circle.fill")
                .foregroundStyle(.green)
                .font(.caption2)
        case .scanning, .connecting:
            ProgressView()
                .controlSize(.small)
        default:
            Image(systemName: "circle.fill")
                .foregroundStyle(.secondary)
                .font(.caption2)
        }
    }
}

private struct SensorStatusRow: View {
    let connectionState: BLEManager.ConnectionState
    let deviceStatus: DeviceStatus?
    /// Whether the sensor is actually reporting cadence (see `sensorIsLive`).
    let isLive: Bool

    var body: some View {
        HStack {
            Text("Cadence")
            Spacer()
            batteryView
            statusIcon
        }
    }

    @ViewBuilder
    private var batteryView: some View {
        // Show the battery whenever the sensor has reported it — independent of the
        // live state, since the battery report lags behind the cadence stream.
        if case .connected = connectionState, let bat = deviceStatus?.sensorBattery {
            Text("\(bat)%")
                .foregroundStyle(.secondary)
                .font(.subheadline)
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch connectionState {
        case .connected:
            if isLive {
                Image(systemName: "circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption2)
            } else {
                Text("Searching…")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
        case .scanning, .connecting:
            ProgressView()
                .controlSize(.small)
        default:
            Image(systemName: "circle.fill")
                .foregroundStyle(.secondary)
                .font(.caption2)
        }
    }
}

private struct RidingRow: View {
    @Environment(AppSettings.self) private var settings
    let ride: Ride
    let now: Date

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "bicycle")
                .foregroundStyle(.red)
            Text("Riding")
                .fontWeight(.semibold)
                .foregroundStyle(.red)
            Spacer()
            Text(distance)
                .foregroundStyle(.secondary)
            Divider()
                .frame(height: 20)
            Text(elapsed)
                .foregroundStyle(.secondary)
        }
    }

    private var elapsed: String {
        Duration.seconds(now.timeIntervalSince(ride.startDate))
            .formatted(.time(pattern: .hourMinuteSecond(padHourToLength: 2)))
    }

    private var distance: String {
        let config = CalculateMetrics.Config(
            gearRatio: settings.gearRatio,
            wheelCircumferenceMeters: settings.wheelCircumferenceMeters
        )
        let meters = CalculateMetrics.cadenceDistance(points: ride.points, config: config)
        return Measurement(value: meters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }
}

private struct CompletedRideRow: View {
    let ride: Ride
    @Environment(AppSettings.self) private var settings

    var body: some View {
        let config = CalculateMetrics.Config(
            gearRatio: settings.gearRatio,
            wheelCircumferenceMeters: settings.wheelCircumferenceMeters
        )
        let metrics = CalculateMetrics.compute(ride: ride, config: config)
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(ride.startDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.headline)
                Text("\(ride.startDate.formatted(date: .omitted, time: .shortened)) – \(ride.endDate.formatted(date: .omitted, time: .shortened))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(
                    Measurement(value: metrics.totalDistanceMeters, unit: UnitLength.meters)
                        .formatted(.measurement(width: .abbreviated, usage: .road))
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                Text(detail(metrics))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func detail(_ metrics: RideMetrics) -> String {
        let duration = Duration.seconds(ride.duration).formatted(.time(pattern: .hourMinute))
        guard metrics.averageCadenceRpm > 0 else { return duration }
        return "\(duration) · \(Int(metrics.averageCadenceRpm)) rpm"
    }
}

private struct CurrentValuesRow: View {
    let rpm: Int
    let location: CLLocationCoordinate2D?

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Label("Cadence", systemImage: "arrow.clockwise")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(rpm) rpm")
                    .font(.title3.monospacedDigit())
                    .fontWeight(.medium)
            }
            if let location {
                HStack {
                    Label("Location", systemImage: "location.fill")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.5f, %.5f", location.latitude, location.longitude))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct EmptyRidesView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "bicycle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No rides yet")
                .font(.headline)
            Text("Connect your device and start pedaling.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}
