import Foundation

/// Global, fixed rules for Blast Ball stage progression.
enum StageRules {
    static let totalStages = 1_000
    /// Absolute cap on simultaneously active balls. Never changes.
    static let maxSimultaneousBalls = 10

    /// The stage number IS the number of successful blasts required.
    static func requiredBlasts(for stage: Int) -> Int {
        precondition((1...totalStages).contains(stage), "Stage out of range: \(stage)")
        return stage
    }
}

/// Per-stage tuning values. The ball count is NOT here on purpose —
/// difficulty never changes how many balls a stage requires.
struct StageDifficulty: Equatable {
    /// Ball speed in points per second (randomised within this range).
    let speedRange: ClosedRange<Double>
    /// Pause between one wave being cleared and the next spawning.
    let interWaveDelay: TimeInterval
    /// Max angle (radians) a ball's heading may deviate from "straight across".
    let trajectorySpread: Double
    /// Weighting toward bigger waves: 0 = uniform 1…max, 1 = strongly favour max.
    let largeWaveBias: Double
    /// Chance (0…1) that a given ball is a special ball.
    let specialBallChance: Double
}

/// Configurable difficulty curve over stages 1…1000.
/// Every value interpolates smoothly from `easy` (stage 1) to `hard` (stage 1000)
/// using an ease-out curve, so early stages ramp up quickly and late stages
/// stay hard without becoming unplayable. Tune these numbers during playtesting.
struct DifficultyCurve {
    var minSpeed: ClosedRange<Double> = 90...140      // stage 1
    var maxSpeed: ClosedRange<Double> = 260...360     // stage 1000
    var delay: (easy: Double, hard: Double) = (1.2, 0.25)
    var spread: (easy: Double, hard: Double) = (0.15, 0.9)
    var waveBias: (easy: Double, hard: Double) = (0.0, 0.75)
    var specialChance: (easy: Double, hard: Double) = (0.0, 0.25)
    /// Stage at which special balls may start appearing.
    var specialBallsFromStage = 50
    /// Curve exponent: < 1 front-loads difficulty, > 1 back-loads it.
    var exponent = 0.6

    static let `default` = DifficultyCurve()

    func difficulty(for stage: Int) -> StageDifficulty {
        let clamped = min(max(stage, 1), StageRules.totalStages)
        let linear = Double(clamped - 1) / Double(StageRules.totalStages - 1)
        let t = pow(linear, exponent)

        func lerp(_ a: Double, _ b: Double) -> Double { a + (b - a) * t }

        let low = lerp(minSpeed.lowerBound, maxSpeed.lowerBound)
        let high = lerp(minSpeed.upperBound, maxSpeed.upperBound)

        return StageDifficulty(
            speedRange: low...high,
            interWaveDelay: lerp(delay.easy, delay.hard),
            trajectorySpread: lerp(spread.easy, spread.hard),
            largeWaveBias: lerp(waveBias.easy, waveBias.hard),
            specialBallChance: clamped >= specialBallsFromStage
                ? lerp(specialChance.easy, specialChance.hard) : 0
        )
    }
}
