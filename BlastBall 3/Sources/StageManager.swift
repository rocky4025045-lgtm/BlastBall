import Foundation

// MARK: - Spawn description (pure data, no SpriteKit)

enum ScreenEdge: CaseIterable { case top, bottom, left, right }

struct BallSpawn: Equatable {
    let id: Int
    let entryEdge: ScreenEdge
    /// 0…1 position along the entry edge (kept away from corners).
    let edgePosition: Double
    /// Heading in radians, pointing into the screen, with random spread applied.
    let heading: Double
    let speed: Double
    let isSpecial: Bool
}

enum StageState: Equatable {
    case ready            // stage initialised, waiting to start
    case waitingForWave   // between waves (inter-wave delay)
    case playing          // a wave is on screen
    case failed           // a ball touched an edge — attempt over
    case stageCompleted   // required blasts reached, screen clear
    case gameCompleted    // stage 1000 finished — show victory screen
}

protocol StageManagerDelegate: AnyObject {
    func stageManager(_ m: StageManager, didSpawnWave balls: [BallSpawn])
    func stageManager(_ m: StageManager, didBlastBall id: Int)
    func stageManager(_ m: StageManager, didFailBecauseBallHitEdge id: Int)
    func stageManagerDidCompleteStage(_ m: StageManager)
    func stageManagerDidCompleteAllStages(_ m: StageManager)
    func stageManagerProgressDidChange(_ m: StageManager)
}

// MARK: - StageManager

/// Owns all stage / wave / blast-count rules. Rendering layer (SpriteKit) only
/// reports events in (`blastBall`, `ballTouchedEdge`) and draws what it is told.
final class StageManager {

    // Required state variables (spec §3)
    private(set) var currentStage: Int
    private(set) var requiredBlasts = 0
    private(set) var successfulBlasts = 0
    var remainingBlasts: Int { requiredBlasts - successfulBlasts }
    var activeBallCount: Int { activeBallIDs.count }
    let maxSimultaneousBalls = StageRules.maxSimultaneousBalls
    private(set) var currentWaveSize = 0

    private(set) var score = 0
    private(set) var state: StageState = .ready
    private(set) var difficulty: StageDifficulty

    // Bookkeeping
    private(set) var activeBallIDs = Set<Int>()
    /// Balls spawned so far this attempt (spawned, not yet blasted, + blasted).
    private(set) var spawnedThisAttempt = 0
    /// History of wave sizes this attempt — handy for tests & analytics.
    private(set) var waveSizes: [Int] = []
    private var nextBallID = 0

    weak var delegate: StageManagerDelegate?
    let curve: DifficultyCurve
    private var rng: AnyRandomNumberGenerator

    init(startingStage: Int = 1,
         curve: DifficultyCurve = .default,
         rng: RandomNumberGenerator = SystemRandomNumberGenerator()) {
        precondition((1...StageRules.totalStages).contains(startingStage))
        self.currentStage = startingStage
        self.curve = curve
        self.rng = AnyRandomNumberGenerator(rng)
        self.difficulty = curve.difficulty(for: startingStage)
        beginStage()
    }

    // MARK: Stage lifecycle

    /// Initialise (or re-initialise) the current stage. Also used for retries.
    func beginStage() {
        requiredBlasts = StageRules.requiredBlasts(for: currentStage)
        successfulBlasts = 0
        activeBallIDs.removeAll()
        spawnedThisAttempt = 0
        currentWaveSize = 0
        waveSizes.removeAll()
        difficulty = curve.difficulty(for: currentStage)
        state = .ready
        delegate?.stageManagerProgressDidChange(self)
    }

    /// Retry after failure. Stage number is unchanged; progress resets.
    func retryStage() {
        guard state == .failed else { return }
        beginStage()
    }

    /// Move on after a completed stage. No-op unless the stage is completed.
    @discardableResult
    func advanceToNextStage() -> Bool {
        guard state == .stageCompleted, currentStage < StageRules.totalStages else { return false }
        currentStage += 1
        beginStage()
        return true
    }

    // MARK: Waves

    /// True when the scene should call `spawnNextWave()` (after its delay).
    var canSpawnWave: Bool {
        (state == .ready || state == .waitingForWave)
            && activeBallIDs.isEmpty
            && spawnedThisAttempt < requiredBlasts
    }

    /// Spawns the next randomized wave. Returns [] if spawning isn't allowed.
    @discardableResult
    func spawnNextWave() -> [BallSpawn] {
        guard canSpawnWave else { return [] }

        let unspawned = requiredBlasts - spawnedThisAttempt
        let cap = min(maxSimultaneousBalls, unspawned)   // never > 10, never > remaining
        let size = randomWaveSize(upTo: cap)

        var balls: [BallSpawn] = []
        balls.reserveCapacity(size)
        for _ in 0..<size { balls.append(makeBall()) }

        currentWaveSize = size
        spawnedThisAttempt += size
        waveSizes.append(size)
        balls.forEach { activeBallIDs.insert($0.id) }
        state = .playing

        assert(activeBallIDs.count <= maxSimultaneousBalls)
        assert(spawnedThisAttempt <= requiredBlasts)

        delegate?.stageManager(self, didSpawnWave: balls)
        delegate?.stageManagerProgressDidChange(self)
        return balls
    }

    /// Random size in 1…cap, optionally biased toward larger waves at high stages.
    private func randomWaveSize(upTo cap: Int) -> Int {
        guard cap > 1 else { return 1 }
        let u = Double.random(in: 0..<1, using: &rng)
        // Bias: raise u to a power < 1 to push results toward the top of the range.
        let biased = pow(u, 1.0 - 0.8 * difficulty.largeWaveBias)
        return min(cap, 1 + Int(biased * Double(cap)))
    }

    private func makeBall() -> BallSpawn {
        defer { nextBallID += 1 }
        let edge = ScreenEdge.allCases.randomElement(using: &rng)!
        let inward: Double
        switch edge {
        case .top: inward = -.pi / 2
        case .bottom: inward = .pi / 2
        case .left: inward = 0
        case .right: inward = .pi
        }
        let spread = difficulty.trajectorySpread
        return BallSpawn(
            id: nextBallID,
            entryEdge: edge,
            edgePosition: Double.random(in: 0.15...0.85, using: &rng),
            heading: inward + Double.random(in: -spread...spread, using: &rng),
            speed: Double.random(in: difficulty.speedRange, using: &rng),
            isSpecial: Double.random(in: 0..<1, using: &rng) < difficulty.specialBallChance
        )
    }

    // MARK: Events from the scene

    /// Call when the player taps a ball. Returns true only for the first,
    /// valid blast of an active ball — duplicate touches are ignored.
    @discardableResult
    func blastBall(id: Int) -> Bool {
        guard state == .playing, activeBallIDs.remove(id) != nil else { return false }

        successfulBlasts += 1
        score += scoreForBlast()
        delegate?.stageManager(self, didBlastBall: id)
        delegate?.stageManagerProgressDidChange(self)

        if activeBallIDs.isEmpty {
            if successfulBlasts == requiredBlasts {
                completeStage()
            } else {
                state = .waitingForWave
            }
        }
        return true
    }

    /// Call when any active ball touches a screen edge. Fails immediately.
    func ballTouchedEdge(id: Int) {
        guard state == .playing, activeBallIDs.contains(id) else { return }
        state = .failed
        // The ball is NOT silently removed from the count; the whole attempt ends.
        delegate?.stageManager(self, didFailBecauseBallHitEdge: id)
    }

    private func scoreForBlast() -> Int {
        // Simple: 10 points, +1 per 10 stages. Swap in your existing scoring.
        10 + currentStage / 10
    }

    private func completeStage() {
        if currentStage == StageRules.totalStages {
            state = .gameCompleted
            delegate?.stageManagerDidCompleteAllStages(self)
        } else {
            state = .stageCompleted
            delegate?.stageManagerDidCompleteStage(self)
        }
    }

    // MARK: HUD strings (spec §6)

    var stageLabel: String { "STAGE \(currentStage) / \(StageRules.totalStages)" }
    var progressLabel: String { "\(successfulBlasts) / \(requiredBlasts)" }
    var remainingLabel: String { "\(remainingBlasts) LEFT" }
    var activeLabel: String { "\(activeBallCount) / \(maxSimultaneousBalls)" }
    var scoreLabel: String { "\(score)" }
}

// MARK: - Type-erased RNG (lets tests inject a seeded generator)

struct AnyRandomNumberGenerator: RandomNumberGenerator {
    private var base: RandomNumberGenerator
    init(_ base: RandomNumberGenerator) { self.base = base }
    mutating func next() -> UInt64 { base.next() }
}

/// Deterministic generator for tests and reproducible playtests (SplitMix64).
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
