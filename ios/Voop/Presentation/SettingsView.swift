import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var exportFile: ExportFile?

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section {
                    Picker("Wheel size", selection: $settings.rimBsdMillimeters) {
                        ForEach(AppSettings.rimPresets, id: \.bsd) { rim in
                            Text(rim.label).tag(rim.bsd)
                        }
                    }
                    Stepper(value: $settings.tireWidthMillimeters, in: 18...60) {
                        LabeledContent("Tire") {
                            Text("\(settings.tireWidthMillimeters) mm")
                                .foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("Circumference") {
                        Text("\(settings.wheelCircumferenceMeters, format: .number.precision(.fractionLength(3))) m")
                            .foregroundStyle(.secondary)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(AppSettings.tirePresets, id: \.label) { preset in
                                let active = settings.rimBsdMillimeters == preset.bsd
                                    && settings.tireWidthMillimeters == preset.width
                                Button(preset.label) {
                                    settings.rimBsdMillimeters = preset.bsd
                                    settings.tireWidthMillimeters = preset.width
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .tint(active ? .accentColor : .secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("Wheel")
                } footer: {
                    Text(
                        "Rim size × tire width gives the rolling circumference, combined with the " +
                            "gear to turn pedal revolutions into distance."
                    )
                }

                Section {
                    Stepper(value: $settings.chainringTeeth, in: 20...60) {
                        LabeledContent("Chainring") {
                            Text("\(settings.chainringTeeth)t")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Stepper(value: $settings.cogTeeth, in: 9...30) {
                        LabeledContent("Cog") {
                            Text("\(settings.cogTeeth)t")
                                .foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("Ratio") {
                        Text("\(settings.gearRatio, format: .number.precision(.fractionLength(2)))")
                            .foregroundStyle(.secondary)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(AppSettings.gearPresets, id: \.label) { preset in
                                let active = settings.chainringTeeth == preset.chainring
                                    && settings.cogTeeth == preset.cog
                                Button(preset.label) {
                                    settings.chainringTeeth = preset.chainring
                                    settings.cogTeeth = preset.cog
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .tint(active ? .accentColor : .secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("Gear")
                } footer: {
                    Text("Chainring ÷ cog teeth. Combined with wheel size to turn pedal revolutions into distance.")
                }

                Section {
                    Stepper(value: $settings.minCadenceRpm, in: 5...60, step: 5) {
                        LabeledContent("Min cadence") {
                            Text("\(settings.minCadenceRpm) rpm")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Stepper(value: $settings.minDistanceMeters, in: 0...5000, step: 100) {
                        LabeledContent("Min distance") {
                            Text(
                                Measurement(value: Double(settings.minDistanceMeters), unit: UnitLength.meters)
                                    .formatted(.measurement(width: .abbreviated, usage: .road))
                            )
                            .foregroundStyle(.secondary)
                        }
                    }
                    Stepper(value: $settings.gapThresholdSeconds, in: 60...1800, step: 60) {
                        LabeledContent("Stop pause") {
                            Text(
                                Duration.seconds(settings.gapThresholdSeconds)
                                    .formatted(.units(allowed: [.minutes], width: .abbreviated))
                            )
                            .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Ride detection")
                } footer: {
                    Text(
                        "A segment counts as a ride only if it stays above the cadence and reaches " +
                            "the distance — filters out walking a fixed gear bike or short rolls. A pause " +
                            "longer than the stop pause ends a ride and clears the live card."
                    )
                }

                Section {
                    Button {
                        if let url = try? appModel.writeCSVExport() {
                            exportFile = ExportFile(url: url)
                        }
                    } label: {
                        Label("Export raw data (CSV)", systemImage: "square.and.arrow.up")
                    }
                } header: {
                    Text("Debug")
                } footer: {
                    Text("Exports every recorded data point as CSV for troubleshooting.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $exportFile) { file in
                ActivityView(activityItems: [file.url])
            }
        }
    }
}

private struct ExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
