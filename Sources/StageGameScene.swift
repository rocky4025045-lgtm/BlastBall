import SpriteKit
import UIKit

/// SpriteKit layer wired to StageManager. Merge into your existing GameScene:
/// keep your art/sounds, but route spawns, taps and edge hits through `stages`.
final class StageGameScene: SKScene, StageManagerDelegate {

    var stages: StageManager!
    private var ballNodes: [Int: SKShapeNode] = [:]
    private var velocities: [Int: CGVector] = [:]
    private let ballRadius: CGFloat = 28
    private let haptic = UIImpactFeedbackGenerator(style: .medium)

    // HUD
    private let stageLabel = SKLabelNode(fontNamed: "Menlo-Bold")
    private let progressLabel = SKLabelNode(fontNamed: "Menlo-Bold")
    private let remainingLabel = SKLabelNode(fontNamed: "Menlo")
    private let activeLabel = SKLabelNode(fontNamed: "Menlo")
    private let scoreLabel = SKLabelNode(fontNamed: "Menlo-Bold")

    // MARK: Setup

    override func didMove(to view: SKView) {
        backgroundColor = .black
        physicsWorld.gravity = .zero          // no physics edges → no bouncing
        if stages == nil { stages = StageManager(startingStage: 1) }
        stages.delegate = self
        setUpHUD()
        refreshHUD()
        scheduleNextWave()
    }

    private func setUpHUD() {
        let safeTop = size.height - (view?.safeAreaInsets.top ?? 44) - 24
        let items: [(SKLabelNode, CGFloat, CGFloat, SKLabelHorizontalAlignmentMode)] = [
            (stageLabel, 20, safeTop, .left),
            (scoreLabel, size.width - 20, safeTop, .right),
            (progressLabel, 20, safeTop - 26, .left),
            (remainingLabel, size.width / 2, safeTop - 26, .center),
            (activeLabel, size.width - 20, safeTop - 26, .right),
        ]
        for (label, x, y, align) in items {
            label.fontSize = 16
            label.fontColor = UIColor(white: 0.85, alpha: 1)
            label.horizontalAlignmentMode = align
            label.position = CGPoint(x: x, y: y)
            label.zPosition = 100
            addChild(label)
        }
        stageLabel.fontColor = .white
    }

    private func refreshHUD() {
        stageLabel.text = stages.stageLabel
        progressLabel.text = stages.progressLabel
        remainingLabel.text = stages.remainingLabel
        activeLabel.text = stages.activeLabel
        scoreLabel.text = stages.scoreLabel
    }

    // MARK: Waves

    private func scheduleNextWave() {
        guard stages.canSpawnWave else { return }
        let delay = stages.state == .ready ? 0.6 : stages.difficulty.interWaveDelay
        removeAction(forKey: "wave")
        run(.sequence([.wait(forDuration: delay),
                       .run { [weak self] in self?.stages.spawnNextWave() }]),
            withKey: "wave")
    }

    func stageManager(_ m: StageManager, didSpawnWave balls: [BallSpawn]) {
        for spawn in balls { addBall(spawn) }
    }

    private func addBall(_ spawn: BallSpawn) {
        // Start fully inside the screen, just off the entry edge, so the ball is
        // never touching an edge at birth.
        let inset = ballRadius + 6
        let p = CGFloat(spawn.edgePosition)
        let pos: CGPoint
        switch spawn.entryEdge {
        case .top:    pos = CGPoint(x: p * size.width, y: size.height - inset)
        case .bottom: pos = CGPoint(x: p * size.width, y: inset)
        case .left:   pos = CGPoint(x: inset, y: p * size.height)
        case .right:  pos = CGPoint(x: size.width - inset, y: p * size.height)
        }
        let node = SKShapeNode(circleOfRadius: ballRadius)
        node.fillColor = spawn.isSpecial ? .systemYellow : .systemPink
        node.strokeColor = .clear
        node.position = pos
        node.name = "ball-\(spawn.id)"
        node.setScale(0.1)
        node.run(.scale(to: 1, duration: 0.15))
        addChild(node)

        ballNodes[spawn.id] = node
        velocities[spawn.id] = CGVector(dx: CGFloat(cos(spawn.heading) * spawn.speed),
                                        dy: CGFloat(sin(spawn.heading) * spawn.speed))
    }

    // MARK: Movement + edge detection (no bounce, no wrap)

    private var lastTime: TimeInterval = 0

    override func update(_ currentTime: TimeInterval) {
        let dt = lastTime == 0 ? 0 : min(currentTime - lastTime, 1.0 / 30)
        lastTime = currentTime
        guard stages.state == .playing else { return }

        for (id, node) in ballNodes {
            guard let v = velocities[id] else { continue }
            node.position.x += v.dx * CGFloat(dt)
            node.position.y += v.dy * CGFloat(dt)

            let p = node.position
            if p.x - ballRadius <= 0 || p.x + ballRadius >= size.width ||
               p.y - ballRadius <= 0 || p.y + ballRadius >= size.height {
                stages.ballTouchedEdge(id: id)   // fails the attempt immediately
                return
            }
        }
    }

    // MARK: Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        switch stages.state {
        case .failed: stages.retryStage(); clearBalls(); refreshHUD(); scheduleNextWave(); return
        case .stageCompleted:
            if stages.advanceToNextStage() {
                UserDefaults.standard.set(stages.currentStage, forKey: "blastball.currentStage")
                clearBalls(); refreshHUD(); scheduleNextWave()
            }
            return
        default: break
        }
        for touch in touches {
            let loc = touch.location(in: self)
            // Nearest ball under the finger; each ball can only count once.
            if let hit = ballNodes.first(where: { $0.value.position.distance(to: loc) <= ballRadius * 1.25 }) {
                stages.blastBall(id: hit.key)
            }
        }
    }

    func stageManager(_ m: StageManager, didBlastBall id: Int) {
        guard let node = ballNodes.removeValue(forKey: id) else { return }
        velocities[id] = nil
        haptic.impactOccurred()
        node.run(.sequence([.group([.scale(to: 1.8, duration: 0.12),
                                    .fadeOut(withDuration: 0.12)]),
                            .removeFromParent()]))
        if m.state == .waitingForWave { scheduleNextWave() }
    }

    func stageManager(_ m: StageManager, didFailBecauseBallHitEdge id: Int) {
        ballNodes[id]?.fillColor = .systemRed
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        removeAction(forKey: "wave")
        showBanner("MISSED — TAP TO RETRY", color: .systemRed)
    }

    func stageManagerDidCompleteStage(_ m: StageManager) {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        showBanner("STAGE \(m.currentStage) CLEAR — TAP", color: .systemGreen)
    }

    func stageManagerDidCompleteAllStages(_ m: StageManager) {
        // Final victory screen — replace with your own scene/view if you have one.
        let victory = SKLabelNode(fontNamed: "Menlo-Bold")
        victory.text = "ALL 1000 STAGES COMPLETE"
        victory.fontSize = 24
        victory.fontColor = .systemYellow
        victory.position = CGPoint(x: size.width / 2, y: size.height / 2)
        victory.name = "victory"
        addChild(victory)
        victory.run(.repeatForever(.sequence([.scale(to: 1.1, duration: 0.5),
                                              .scale(to: 1.0, duration: 0.5)])))
    }

    func stageManagerProgressDidChange(_ m: StageManager) { refreshHUD() }

    // MARK: Helpers

    private func clearBalls() {
        ballNodes.values.forEach { $0.removeFromParent() }
        ballNodes.removeAll(); velocities.removeAll()
        childNode(withName: "banner")?.removeFromParent()
    }

    private func showBanner(_ text: String, color: UIColor) {
        childNode(withName: "banner")?.removeFromParent()
        let label = SKLabelNode(fontNamed: "Menlo-Bold")
        label.text = text
        label.fontSize = 20
        label.fontColor = color
        label.position = CGPoint(x: size.width / 2, y: size.height / 2)
        label.name = "banner"
        label.zPosition = 200
        addChild(label)
    }
}

private extension CGPoint {
    func distance(to o: CGPoint) -> CGFloat { hypot(x - o.x, y - o.y) }
}
