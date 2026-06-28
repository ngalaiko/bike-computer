import Foundation
import Observation

@Observable
final class AppSettings {
    var rimBsdMillimeters: Int {
        didSet { UserDefaults.standard.set(rimBsdMillimeters, forKey: "rimBsdMillimeters") }
    }
    var tireWidthMillimeters: Int {
        didSet { UserDefaults.standard.set(tireWidthMillimeters, forKey: "tireWidthMillimeters") }
    }
    var chainringTeeth: Int {
        didSet { UserDefaults.standard.set(chainringTeeth, forKey: "chainringTeeth") }
    }
    var cogTeeth: Int {
        didSet { UserDefaults.standard.set(cogTeeth, forKey: "cogTeeth") }
    }
    var minCadenceRpm: Int {
        didSet { UserDefaults.standard.set(minCadenceRpm, forKey: "minCadenceRpm") }
    }
    var minDistanceMeters: Int {
        didSet { UserDefaults.standard.set(minDistanceMeters, forKey: "minDistanceMeters") }
    }
    var gapThresholdSeconds: Int {
        didSet { UserDefaults.standard.set(gapThresholdSeconds, forKey: "gapThresholdSeconds") }
    }

    /// Rolling circumference from rim bead-seat diameter + tire, treating the wheel as a
    /// circle of diameter BSD + 2×tire width.
    var wheelCircumferenceMeters: Double {
        Double.pi * Double(rimBsdMillimeters + 2 * tireWidthMillimeters) / 1000.0
    }

    /// Chainring teeth ÷ cog teeth — how far the wheel turns per crank revolution.
    var gearRatio: Double {
        Double(chainringTeeth) / Double(cogTeeth)
    }

    /// A pause longer than this ends a ride and clears the live card.
    var gapThreshold: TimeInterval {
        TimeInterval(gapThresholdSeconds)
    }

    static let rimPresets: [(label: String, bsd: Int)] = [
        ("700c", 622),
        ("650b", 584),
        ("26\"", 559),
    ]

    static let tirePresets: [(label: String, bsd: Int, width: Int)] = [
        ("700×25c", 622, 25),
        ("700×28c", 622, 28),
        ("700×32c", 622, 32),
        ("650×47b", 584, 47),
    ]

    static let gearPresets: [(label: String, chainring: Int, cog: Int)] = [
        ("46×16", 46, 16),
        ("48×17", 48, 17),
        ("44×16", 44, 16),
        ("46×18", 46, 18),
    ]

    init() {
        let bsd = UserDefaults.standard.integer(forKey: "rimBsdMillimeters")
        rimBsdMillimeters = bsd > 0 ? bsd : 622
        let width = UserDefaults.standard.integer(forKey: "tireWidthMillimeters")
        tireWidthMillimeters = width > 0 ? width : 25
        let chain = UserDefaults.standard.integer(forKey: "chainringTeeth")
        chainringTeeth = chain > 0 ? chain : 46
        let cog = UserDefaults.standard.integer(forKey: "cogTeeth")
        cogTeeth = cog > 0 ? cog : 16
        let m = UserDefaults.standard.integer(forKey: "minCadenceRpm")
        minCadenceRpm = m > 0 ? m : 20
        let d = UserDefaults.standard.integer(forKey: "minDistanceMeters")
        minDistanceMeters = d > 0 ? d : 500
        let gap = UserDefaults.standard.integer(forKey: "gapThresholdSeconds")
        gapThresholdSeconds = gap > 0 ? gap : 5 * 60
    }
}
