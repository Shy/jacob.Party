import SwiftUI
import SceneKit

struct PartyButton3DView: View {
    let isPartyMode: Bool
    let isPressed: Bool

    var body: some View {
        ZStack {
            // Glow effect when party mode is active
            if isPartyMode {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.red.opacity(0.6),
                                Color.orange.opacity(0.4),
                                Color.yellow.opacity(0.2),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 80,
                            endRadius: 200
                        )
                    )
                    .frame(width: 400, height: 400)
                    .blur(radius: 50)
                    .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: isPartyMode)
                    .transition(.scale.combined(with: .opacity))
            }

            // 3D Button
            PartyButtonSceneView(isPartyMode: isPartyMode, isPressed: isPressed)
                .frame(width: 350, height: 350)
                .scaleEffect(isPressed ? 0.95 : 1.0) // Press feedback
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)

            // Confetti particles when party mode is active
            if isPartyMode {
                ForEach(0..<20, id: \.self) { index in
                    ConfettiParticle(index: index)
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: isPartyMode)
    }
}

struct PartyButtonSceneView: UIViewRepresentable {
    let isPartyMode: Bool
    let isPressed: Bool

    func makeUIView(context: Context) -> SCNView {
        let sceneView = SCNView()
        sceneView.scene = createScene()
        sceneView.backgroundColor = UIColor.clear
        sceneView.autoenablesDefaultLighting = false
        sceneView.allowsCameraControl = false

        if let scene = sceneView.scene {
            scene.background.contents = UIColor.clear
        }

        return sceneView
    }

    func updateUIView(_ sceneView: SCNView, context: Context) {
        guard let scene = sceneView.scene else { return }

        // Update button position (pressed state)
        if let buttonNode = scene.rootNode.childNode(withName: "button", recursively: false) {
            let targetY: Float = isPressed ? -0.15 : 0.0

            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.15
            buttonNode.position.y = targetY
            SCNTransaction.commit()
        }

        // Update materials and lights
        updateMaterials(in: scene)
        updateLights(in: scene)
    }

    private func createScene() -> SCNScene {
        let scene = SCNScene()

        // Create button base/platform (gray base that button sits on)
        let baseGeometry = SCNCylinder(radius: 1.3, height: 0.3)
        let baseMaterial = SCNMaterial()
        baseMaterial.lightingModel = .physicallyBased
        baseMaterial.diffuse.contents = UIColor(white: 0.2, alpha: 1.0)
        baseMaterial.metalness.contents = 0.8
        baseMaterial.roughness.contents = 0.3
        baseGeometry.materials = [baseMaterial]

        let baseNode = SCNNode(geometry: baseGeometry)
        baseNode.position = SCNVector3(0, -0.5, 0)
        scene.rootNode.addChildNode(baseNode)

        // Create the button (red cylinder)
        let buttonGeometry = SCNCylinder(radius: 1.2, height: 0.6)
        let buttonMaterial = SCNMaterial()
        buttonMaterial.lightingModel = .physicallyBased
        buttonMaterial.diffuse.contents = UIColor.red
        buttonMaterial.metalness.contents = 0.3
        buttonMaterial.roughness.contents = 0.4
        buttonMaterial.specular.contents = UIColor.white
        buttonGeometry.materials = [buttonMaterial]

        let buttonNode = SCNNode(geometry: buttonGeometry)
        buttonNode.name = "button"
        buttonNode.position = SCNVector3(0, 0, 0)
        scene.rootNode.addChildNode(buttonNode)

        // Add "PARTY" text on button
        let textGeometry = SCNText(string: "PARTY", extrusionDepth: 0.1)
        textGeometry.font = UIFont.systemFont(ofSize: 0.35, weight: .black)
        textGeometry.flatness = 0.01
        textGeometry.chamferRadius = 0.01

        let textMaterial = SCNMaterial()
        textMaterial.diffuse.contents = UIColor.white
        textGeometry.materials = [textMaterial]

        let textNode = SCNNode(geometry: textGeometry)
        textNode.name = "text"

        // Center the text
        let (min, max) = textNode.boundingBox
        let textWidth = CGFloat(max.x - min.x)
        let textHeight = CGFloat(max.y - min.y)
        textNode.position = SCNVector3(-Float(textWidth) / 2, -Float(textHeight) / 2 + 0.1, 0.35)

        buttonNode.addChildNode(textNode)

        // Camera
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(x: 0, y: 1, z: 4)
        cameraNode.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(cameraNode)

        // Setup lights
        setupLights(in: scene)

        return scene
    }

    private func setupLights(in scene: SCNScene) {
        // Main spotlight from above
        let mainLight = SCNNode()
        mainLight.name = "mainLight"
        mainLight.light = SCNLight()
        mainLight.light?.type = .spot
        mainLight.light?.spotInnerAngle = 30
        mainLight.light?.spotOuterAngle = 60
        mainLight.position = SCNVector3(0, 5, 3)
        mainLight.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(mainLight)

        // Rim lights (colored)
        let redLight = SCNNode()
        redLight.name = "redLight"
        redLight.light = SCNLight()
        redLight.light?.type = .omni
        redLight.light?.color = UIColor.red
        redLight.position = SCNVector3(3, 1, 2)
        scene.rootNode.addChildNode(redLight)

        let yellowLight = SCNNode()
        yellowLight.name = "yellowLight"
        yellowLight.light = SCNLight()
        yellowLight.light?.type = .omni
        yellowLight.light?.color = UIColor.yellow
        yellowLight.position = SCNVector3(-3, 1, 2)
        scene.rootNode.addChildNode(yellowLight)

        let blueLight = SCNNode()
        blueLight.name = "blueLight"
        blueLight.light = SCNLight()
        blueLight.light?.type = .omni
        blueLight.light?.color = UIColor.cyan
        blueLight.position = SCNVector3(0, 1, -3)
        scene.rootNode.addChildNode(blueLight)

        // Ambient light
        let ambientLight = SCNNode()
        ambientLight.name = "ambientLight"
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        scene.rootNode.addChildNode(ambientLight)
    }

    private func updateLights(in scene: SCNScene) {
        if isPartyMode {
            scene.rootNode.childNode(withName: "mainLight", recursively: false)?.light?.intensity = 2000
            scene.rootNode.childNode(withName: "mainLight", recursively: false)?.light?.color = UIColor.white

            scene.rootNode.childNode(withName: "redLight", recursively: false)?.light?.intensity = 1200
            scene.rootNode.childNode(withName: "yellowLight", recursively: false)?.light?.intensity = 1200
            scene.rootNode.childNode(withName: "blueLight", recursively: false)?.light?.intensity = 1200
            scene.rootNode.childNode(withName: "ambientLight", recursively: false)?.light?.color = UIColor(white: 0.4, alpha: 1.0)
        } else {
            scene.rootNode.childNode(withName: "mainLight", recursively: false)?.light?.intensity = 800
            scene.rootNode.childNode(withName: "mainLight", recursively: false)?.light?.color = UIColor.white

            scene.rootNode.childNode(withName: "redLight", recursively: false)?.light?.intensity = 0
            scene.rootNode.childNode(withName: "yellowLight", recursively: false)?.light?.intensity = 0
            scene.rootNode.childNode(withName: "blueLight", recursively: false)?.light?.intensity = 0
            scene.rootNode.childNode(withName: "ambientLight", recursively: false)?.light?.color = UIColor(white: 0.15, alpha: 1.0)
        }
    }

    private func updateMaterials(in scene: SCNScene) {
        guard let buttonNode = scene.rootNode.childNode(withName: "button", recursively: false),
              let buttonMaterial = buttonNode.geometry?.firstMaterial else { return }

        if isPartyMode {
            // Bright vibrant red when active
            buttonMaterial.diffuse.contents = UIColor(red: 1.0, green: 0.1, blue: 0.1, alpha: 1.0)
            buttonMaterial.emission.contents = UIColor(red: 0.5, green: 0.0, blue: 0.0, alpha: 1.0)
        } else {
            // Dull dark red when inactive
            buttonMaterial.diffuse.contents = UIColor(red: 0.5, green: 0.1, blue: 0.1, alpha: 1.0)
            buttonMaterial.emission.contents = UIColor.black
        }
    }
}

struct ConfettiParticle: View {
    let index: Int
    @State private var offset: CGFloat = 0
    @State private var rotation: Double = 0
    @State private var opacity: Double = 0

    let colors: [Color] = [.red, .yellow, .blue, .green, .purple, .pink, .orange]

    var body: some View {
        let angle = Double(index) * (360.0 / 20.0)
        let distance: CGFloat = 180 + CGFloat.random(in: 0...40)

        RoundedRectangle(cornerRadius: 2)
            .fill(colors[index % colors.count])
            .frame(width: 8, height: 12)
            .rotationEffect(.degrees(rotation))
            .offset(
                x: cos(angle * .pi / 180) * (distance + offset),
                y: sin(angle * .pi / 180) * (distance + offset)
            )
            .opacity(opacity)
            .onAppear {
                withAnimation(
                    .easeOut(duration: 1.5)
                    .repeatForever(autoreverses: false)
                    .delay(Double(index) * 0.05)
                ) {
                    offset = 100
                    opacity = 0
                }

                withAnimation(
                    .linear(duration: 1.0)
                    .repeatForever(autoreverses: false)
                ) {
                    rotation = 360
                }

                opacity = 1.0
            }
    }
}

#Preview {
    ZStack {
        Color.black
        PartyButton3DView(isPartyMode: true, isPressed: false)
    }
}
