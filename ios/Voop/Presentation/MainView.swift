import SwiftUI

struct MainView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 30)) { ctx in
                let ongoing = ongoingRide(at: ctx.date)
                let completed = completedRides(at: ctx.date)
                List {
                    StatusStrip(
                        connectionState: appModel.ble.connectionState,
                        deviceStatus: appModel.ble.deviceStatus
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                    if let ride = ongoing {
                        Section {
                            OngoingRideRow(ride: ride, now: ctx.date)
                        }
                    }

                    if !completed.isEmpty {
                        Section("Rides") {
                            ForEach(Array(completed.reversed())) { ride in
                                NavigationLink(destination: RideDetailView(ride: ride)) {
                                    CompletedRideRow(ride: ride)
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
        }
    }

    private func ongoingRide(at now: Date) -> Ride? {
        guard let last = appModel.detectedRides.last,
              now.timeIntervalSince(last.endDate) < DetectRides.gapThreshold
        else { return nil }
        return last
    }

    private func completedRides(at now: Date) -> [Ride] {
        let rides = appModel.detectedRides
        if let last = rides.last,
           now.timeIntervalSince(last.endDate) < DetectRides.gapThreshold {
            return Array(rides.dropLast())
        }
        return rides
    }
}

private struct StatusStrip: View {
    let connectionState: BLEManager.ConnectionState
    let deviceStatus: DeviceStatus?

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
            Text(statusLabel)
                .foregroundStyle(.secondary)
            Spacer()
            if let s = deviceStatus {
                Text(batteryLabel(s))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
    }

    private var dotColor: Color {
        switch connectionState {
        case .connected:
            return deviceStatus?.sensorConnected == true ? .green : .yellow
        case .connecting, .scanning:
            return .yellow
        default:
            return .secondary
        }
    }

    private var statusLabel: String {
        switch connectionState {
        case .connected:
            return deviceStatus?.sensorConnected == true ? "Ready" : "Cadence sensor missing"
        case .connecting:
            return "Connecting…"
        case .scanning:
            return "Searching…"
        default:
            return "Offline"
        }
    }

    private func batteryLabel(_ s: DeviceStatus) -> String {
        if let sensorBat = s.sensorBattery {
            return "MCU \(s.mcuBattery.percent)% · SNS \(sensorBat)%"
        }
        return "MCU \(s.mcuBattery.percent)%"
    }
}

private struct PulsingDot: View {
    var body: some View {
        PhaseAnimator([false, true]) { expanded in
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
                .scaleEffect(expanded ? 1.8 : 1.0)
                .opacity(expanded ? 0.35 : 1.0)
        } animation: { expanded in
            expanded ? .easeOut(duration: 0.7) : .easeIn(duration: 0.5)
        }
    }
}

private struct OngoingRideRow: View {
    let ride: Ride
    let now: Date

    var body: some View {
        HStack {
            PulsingDot()
            Text("Live")
                .fontWeight(.semibold)
                .foregroundStyle(.red)
            Spacer()
            Text(elapsed)
                .font(.title2.monospacedDigit())
                .fontWeight(.medium)
        }
        .listRowBackground(Color.red.opacity(0.07))
    }

    private var elapsed: String {
        let s = Int(now.timeIntervalSince(ride.startDate))
        let h = s / 3600
        let m = s % 3600 / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}

private struct CompletedRideRow: View {
    let ride: Ride

    private var distanceMeters: Double {
        CalculateMetrics.totalDistance(points: ride.points)
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(ride.startDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.headline)
                Text(Duration.seconds(ride.duration).formatted(.time(pattern: .hourMinute)))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(
                Measurement(value: distanceMeters, unit: UnitLength.meters)
                    .formatted(.measurement(width: .abbreviated, usage: .road))
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
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
