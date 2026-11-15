import SwiftUI
import SpriteKit

@main
struct BlastBallApp: App {
    var body: some Scene {
        WindowGroup {
            GameContainerView()
                .ignoresSafeArea()
                .statusBarHidden(true)
                .persistentSystemOverlays(.hidden)
        }
    }
}

/// Hosts the SpriteKit scene full-screen and resumes from the last saved stage.
struct GameContainerView: View {
    static let savedStageKey = "blastball.currentStage"

    @State private var scene: StageGameScene = {
        let saved = UserDefaults.standard.integer(forKey: GameContainerView.savedStageKey)
        let start = (1...StageRules.totalStages).contains(saved) ? saved : 1
        let scene = StageGameScene(size: UIScreen.main.bounds.size)
        scene.scaleMode = .resizeFill
        scene.stages = StageManager(startingStage: start)
        return scene
    }()

    var body: some View {
        SpriteView(scene: scene, options: [.ignoresSiblingOrder])
            .background(Color.black)
    }
}
