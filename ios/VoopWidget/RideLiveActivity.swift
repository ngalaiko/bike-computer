import ActivityKit
import SwiftUI
import WidgetKit

struct RideLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RideActivityAttributes.self) { context in
            RideLockScreenView(state: context.state)
                .padding()
                .activityBackgroundTint(Color.black.opacity(0.45))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(context.state.isFinished ? "Ride ended" : "Riding")
                    } icon: {
                        Image(systemName: "bicycle")
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    RideTimerText(state: context.state)
                        .font(.title3.monospacedDigit())
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        RideMetric(value: distanceText(context.state.distanceMeters), caption: "distance")
                        Spacer()
                        RideMetric(value: speedText(context.state.currentSpeedKph), caption: "speed")
                        Spacer()
                        RideMetric(value: "\(context.state.currentCadenceRpm) rpm", caption: "cadence")
                    }
                    .font(.subheadline)
                }
            } compactLeading: {
                Image(systemName: "bicycle")
                    .foregroundStyle(.red)
            } compactTrailing: {
                Text(speedText(context.state.currentSpeedKph))
                    .monospacedDigit()
            } minimal: {
                Image(systemName: "bicycle")
                    .foregroundStyle(.red)
            }
            .keylineTint(.red)
        }
    }
}

private struct RideLockScreenView: View {
    let state: RideActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "bicycle")
                    .foregroundStyle(.red)
                Text(state.isFinished ? "Ride ended" : "Riding")
                    .fontWeight(.semibold)
                    .foregroundStyle(.red)
                Spacer()
                RideTimerText(state: state)
                    .font(.title3.monospacedDigit())
            }
            HStack(spacing: 16) {
                RideMetric(value: distanceText(state.distanceMeters), caption: "distance")
                RideMetric(value: speedText(state.currentSpeedKph), caption: "speed")
                RideMetric(value: "\(state.currentCadenceRpm) rpm", caption: "cadence")
            }
            .font(.subheadline)
        }
    }
}

/// Self-counting elapsed clock. The frozen interval (start...end) makes it stop at the true
/// duration once the ride has ended.
private struct RideTimerText: View {
    let state: RideActivityAttributes.ContentState

    var body: some View {
        Text(timerInterval: state.elapsedInterval, countsDown: false)
            .multilineTextAlignment(.trailing)
    }
}

private struct RideMetric: View {
    let value: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .fontWeight(.medium)
            Text(caption)
                .font(.caption2)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
        }
    }
}

private func distanceText(_ meters: Double) -> String {
    Measurement(value: meters, unit: UnitLength.meters)
        .formatted(.measurement(width: .abbreviated, usage: .road))
}

private func speedText(_ kph: Double) -> String {
    Measurement(value: kph.rounded(), unit: UnitSpeed.kilometersPerHour)
        .formatted(.measurement(width: .abbreviated))
}
