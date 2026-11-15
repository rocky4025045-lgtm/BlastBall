import XCTest
@testable import BlastBall

/// Records delegate callbacks so tests can assert on them.
final class SpyDelegate: StageManagerDelegate {
    var waves: [[BallSpawn]] = []
    var completedStages = 0
    var victoryShown = false
    var failures = 0
    func stageManager(_ m: StageManager, didSpawnWave balls: [BallSpawn]) { waves.append(balls) }
    func stageManager(_ m: StageManager, didBlastBall id: Int) {}
    func stageManager(_ m: StageManager, didFailBecauseBallHitEdge id: Int) { failures += 1 }
    func stageManagerDidCompleteStage(_ m: StageManager) { completedStages += 1 }
    func stageManagerDidCompleteAllStages(_ m: StageManager) { victoryShown = true }
    func stageManagerProgressDidChange(_ m: StageManager) {}
}

final class StageManagerTests: XCTestCase {

    private func makeManager(stage: Int, seed: UInt64 = 42) -> (StageManager, SpyDelegate) {
        let m = StageManager(startingStage: stage, rng: SeededGenerator(seed: seed))
        let spy = SpyDelegate()
        m.delegate = spy
        return (m, spy)
    }

    /// Plays a stage perfectly: spawn waves, blast every ball, until done.
    /// Returns the total number of balls spawned.
    @discardableResult
    private func playPerfectly(_ m: StageManager) -> Int {
        var spawned = 0
        while m.canSpawnWave {
            let wave = m.spawnNextWave()
            XCTAssertLessThanOrEqual(m.activeBallCount, StageRules.maxSimultaneousBalls)
            spawned += wave.count
            wave.forEach { XCTAssertTrue(m.blastBall(id: $0.id)) }
        }
        return spawned
    }

    private func assertStageRequires(_ stage: Int, file: StaticString = #filePath, line: UInt = #line) {
        let (m, _) = makeManager(stage: stage)
        XCTAssertEqual(m.requiredBlasts, stage, file: file, line: line)
        let spawned = playPerfectly(m)
        XCTAssertEqual(m.successfulBlasts, stage, file: file, line: line)
        XCTAssertEqual(spawned, stage, file: file, line: line)
        XCTAssertTrue(m.state == .stageCompleted || m.state == .gameCompleted, file: file, line: line)
    }

    // 1–5
    func test01_stage1RequiresOne()      { assertStageRequires(1) }
    func test02_stage10RequiresTen()     { assertStageRequires(10) }
    func test03_stage20RequiresTwenty()  { assertStageRequires(20) }
    func test04_stage100RequiresHundred() { assertStageRequires(100) }
    func test05_stage1000RequiresThousand() { assertStageRequires(1000) }

    // 6
    func test06_noWaveExceedsTen() {
        for seed in UInt64(1)...50 {
            for stage in [7, 10, 11, 20, 99, 500, 1000] {
                let (m, spy) = makeManager(stage: stage, seed: seed)
                playPerfectly(m)
                for wave in spy.waves {
                    XCTAssertGreaterThanOrEqual(wave.count, 1)
                    XCTAssertLessThanOrEqual(wave.count, 10, "stage \(stage) seed \(seed)")
                }
            }
        }
    }

    // 7
    func test07_totalSpawnedEqualsRequired() {
        for stage in [1, 2, 3, 5, 13, 50, 257, 1000] {
            let (m, spy) = makeManager(stage: stage, seed: UInt64(stage))
            playPerfectly(m)
            XCTAssertEqual(spy.waves.reduce(0) { $0 + $1.count }, stage)
            XCTAssertEqual(m.waveSizes.reduce(0, +), stage)
        }
    }

    // 8
    func test08_cannotCompleteEarly() {
        let (m, _) = makeManager(stage: 20)
        var blasted = 0
        while m.canSpawnWave {
            for ball in m.spawnNextWave() {
                m.blastBall(id: ball.id)
                blasted += 1
                if blasted < 20 { XCTAssertNotEqual(m.state, .stageCompleted) }
            }
        }
        XCTAssertEqual(m.state, .stageCompleted)
        // Duplicate touches on an already-blasted ball never count twice.
        XCTAssertFalse(m.blastBall(id: 0))
        XCTAssertEqual(m.successfulBlasts, 20)
        // Advancing is refused unless the stage is actually completed.
        let (fresh, _) = makeManager(stage: 5)
        XCTAssertFalse(fresh.advanceToNextStage())
        XCTAssertEqual(fresh.currentStage, 5)
    }

    func test08b_duplicateTouchCountsOnce() {
        let (m, _) = makeManager(stage: 10)
        let wave = m.spawnNextWave()
        XCTAssertTrue(m.blastBall(id: wave[0].id))
        XCTAssertFalse(m.blastBall(id: wave[0].id))
        XCTAssertEqual(m.successfulBlasts, 1)
    }

    // 9
    func test09_failureDoesNotAdvance() {
        let (m, spy) = makeManager(stage: 20)
        let wave = m.spawnNextWave()
        if wave.count > 1 { m.blastBall(id: wave[0].id) }
        m.ballTouchedEdge(id: wave.last!.id)

        XCTAssertEqual(m.state, .failed)
        XCTAssertEqual(spy.failures, 1)
        XCTAssertFalse(m.advanceToNextStage())
        XCTAssertEqual(m.currentStage, 20)
        XCTAssertFalse(m.canSpawnWave)
        XCTAssertFalse(m.blastBall(id: wave.last!.id), "No scoring after failure")

        m.retryStage()
        XCTAssertEqual(m.currentStage, 20)
        XCTAssertEqual(m.successfulBlasts, 0)
        XCTAssertEqual(m.requiredBlasts, 20)
        XCTAssertEqual(m.state, .ready)
    }

    // 10
    func test10_nextStageInitialisesCorrectCount() {
        let (m, _) = makeManager(stage: 1)
        for expected in 1...30 {
            XCTAssertEqual(m.currentStage, expected)
            XCTAssertEqual(m.requiredBlasts, expected)
            XCTAssertEqual(m.successfulBlasts, 0)
            XCTAssertEqual(m.remainingBlasts, expected)
            playPerfectly(m)
            XCTAssertTrue(m.advanceToNextStage())
        }
        XCTAssertEqual(m.requiredBlasts, 31)
    }

    // 11
    func test11_noSpawnAfterRequiredReached() {
        let (m, spy) = makeManager(stage: 37)
        playPerfectly(m)
        let wavesBefore = spy.waves.count
        XCTAssertFalse(m.canSpawnWave)
        XCTAssertTrue(m.spawnNextWave().isEmpty)
        XCTAssertEqual(spy.waves.count, wavesBefore)
        XCTAssertEqual(m.activeBallCount, 0)
    }

    func test11b_lastWaveNeverOvershoots() {
        // Mid-stage: unspawned remainder caps the wave size.
        for seed in UInt64(1)...200 {
            let (m, _) = makeManager(stage: 3, seed: seed)
            playPerfectly(m)
            XCTAssertEqual(m.waveSizes.reduce(0, +), 3)
        }
    }

    // 12
    func test12_stage1000ShowsVictory() {
        let (m, spy) = makeManager(stage: 1000)
        playPerfectly(m)
        XCTAssertEqual(m.state, .gameCompleted)
        XCTAssertTrue(spy.victoryShown)
        XCTAssertEqual(spy.completedStages, 0)
        XCTAssertFalse(m.advanceToNextStage(), "No progression beyond 1000")
        XCTAssertEqual(m.currentStage, 1000)
    }

    // Difficulty never changes ball count, and ramps monotonically.
    func test_difficultyCurveRampsWithoutTouchingCount() {
        let curve = DifficultyCurve.default
        let easy = curve.difficulty(for: 1), hard = curve.difficulty(for: 1000)
        XCTAssertLessThan(easy.speedRange.upperBound, hard.speedRange.upperBound)
        XCTAssertGreaterThan(easy.interWaveDelay, hard.interWaveDelay)
        XCTAssertEqual(curve.difficulty(for: 49).specialBallChance, 0)
        for s in [1, 250, 999, 1000] { XCTAssertEqual(StageRules.requiredBlasts(for: s), s) }
    }

    func test_hudLabels() {
        let (m, _) = makeManager(stage: 20)
        XCTAssertEqual(m.stageLabel, "STAGE 20 / 1000")
        XCTAssertEqual(m.progressLabel, "0 / 20")
        XCTAssertEqual(m.remainingLabel, "20 LEFT")
        XCTAssertEqual(m.activeLabel, "0 / 10")
    }
}
