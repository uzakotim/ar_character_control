//
//  ContentView.swift
//  ar_character_control
//
//  Created by Timur Uzakov on 30/12/25.
//

import SwiftUI
import RealityKit
import ARKit
import Combine

final class ControlsProxy: ObservableObject {
    weak var coordinator: ARViewContainer.Coordinator?

    
    func startUp()    { coordinator?.startMoveForward() }
    func startDown()  { coordinator?.startMoveBackward() }
    func startLeft()  { coordinator?.startMoveLeft() }
    func startRight() { coordinator?.startMoveRight() }

    func stop()       { coordinator?.stopMoving() }
    func jump()       { coordinator?.jump() }
}

struct HoldButton: View {
    let systemName: String
    let onPress: () -> Void
    let onRelease: () -> Void

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 44))
            .foregroundStyle(.white)
            .shadow(radius: 2)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in onPress() }
                    .onEnded { _ in onRelease() }
            )
    }
}

final class MarkerAlignmentState: ObservableObject {
    @Published var isMarkerVisible = false
    @Published var isAligned = false
    @Published var alignmentComplete = false

    // Marker pose quality
    @Published var screenDistance: CGFloat = .infinity
    @Published var yawError: Float = .pi
}

struct ContentView : View {
    @StateObject private var controls = ControlsProxy()
    @StateObject var alignmentState = MarkerAlignmentState()

    var body: some View {
        ZStack {
            ARViewContainer(
                controls: controls,
                alignmentState: alignmentState
            )
                .edgesIgnoringSafeArea(.all)
            
            if !alignmentState.alignmentComplete {
                MarkerAlignmentOverlay(state: alignmentState)
            } else {
                // Overlay controls
                VStack {
                    Spacer()
                    HStack {
                        // Bottom-left D-pad
                        VStack(spacing: 8) {
                            HStack { Spacer() }
                            HoldButton(
                                systemName: "arrow.up.circle.fill",
                                onPress: { controls.startUp() },
                                onRelease: { controls.stop() }
                            )
                            
                            HStack(spacing: 16) {
                                HoldButton(
                                    systemName: "arrow.left.circle.fill",
                                    onPress: { controls.startLeft() },
                                    onRelease: { controls.stop() }
                                )
                                
                                HoldButton(
                                    systemName: "arrow.down.circle.fill",
                                    onPress: { controls.startDown() },
                                    onRelease: { controls.stop() }
                                )
                                
                                HoldButton(
                                    systemName: "arrow.right.circle.fill",
                                    onPress: { controls.startRight() },
                                    onRelease: { controls.stop() }
                                )
                            }
                        }
                        .padding(.leading, -500)
                        .padding(.bottom, 24)
                        Spacer()
                        Spacer()
                        
                        // Bottom-right Jump button
                        Button(action: { controls.jump() }) {
                            Text("Jump")
                                .font(.headline)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(.ultraThinMaterial, in: Capsule())
                                .foregroundStyle(.white)
                                .shadow(radius: 2)
                        }
                        .padding(.trailing, 20)
                        .padding(.bottom, 24)
                    }
                }
            }
        }
    }
}

struct ARViewContainer: UIViewRepresentable {
    let controls: ControlsProxy
    let alignmentState: MarkerAlignmentState

    func makeCoordinator() -> Coordinator {
        let c = Coordinator()
        c.alignmentState = alignmentState
        return c
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)

        // Configure AR session for horizontal plane detection
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        config.environmentTexturing = .automatic

        // 🔑 Image detection (Solution B: load from Assets)
        guard
            let uiImage = UIImage(named: "marker"),
            let cgImage = uiImage.cgImage
        else {
            fatalError("❌ marker image not found in Assets")
        }

        let referenceImage = ARReferenceImage(
            cgImage,
            orientation: .up,
            physicalWidth: 0.043   // ⬅️ MUST match real printed size (meters)
        )

        config.detectionImages = [referenceImage]
        config.maximumNumberOfTrackedImages = 1


        arView.session.run(config)
        arView.session.delegate = context.coordinator


        // Optional: show detected planes for debugging
//         arView.debugOptions.insert(.showAnchorGeometry)
//         arView.debugOptions.insert(.showFeaturePoints)

        // Wire up coordinator
        context.coordinator.arView = arView
        controls.coordinator = context.coordinator

        // Add tap gesture recognizer to place the pod on a detected plane
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        arView.addGestureRecognizer(tapGesture)

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        // Nothing to update per-frame from SwiftUI state for now
    }
    
    
    

    class Coordinator: NSObject, ARSessionDelegate {
        enum ControlState {
            case idle
            case moving
            case jumping
        }
        weak var alignmentState: MarkerAlignmentState?

        private var worldRoot = Entity()
        private var alignmentStartTime: TimeInterval?

        var controlState: ControlState = .idle
        weak var arView: ARView?
        var podAnchor: AnchorEntity?
        var character: Entity?
        var isJumping = false
        var cameraUpdateCancellable: Cancellable?
        var moveDirection = SIMD3<Float>.zero
        let moveSpeed: Float = 0.5   // meters per second (tune)
        private var updateCancellable: Cancellable?
        
        
        
        func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
            guard
                let arView = arView,
                let alignmentState = alignmentState,
                alignmentState.alignmentComplete == false
            else { return }

            for anchor in anchors {
                guard let imageAnchor = anchor as? ARImageAnchor else { continue }

                alignmentState.isMarkerVisible = true

                // Project marker into screen space
                let worldPos = imageAnchor.transform.columns.3.xyz
                guard let screenPos = arView.project(worldPos)
                else { return }

                let center = CGPoint(
                    x: arView.bounds.midX,
                    y: arView.bounds.midY
                )

                let distance = hypot(
                    screenPos.x - center.x,
                    screenPos.y - center.y
                )

                alignmentState.screenDistance = distance

                // Yaw-only error
                let yaw = extractYaw(from: imageAnchor.transform)
                alignmentState.yawError = abs(yaw)

                let aligned =
                    distance < 40 &&
                    alignmentState.yawError < 0.15

                alignmentState.isAligned = aligned

                if aligned {
                    let now = CACurrentMediaTime()
                    if alignmentStartTime == nil {
                        alignmentStartTime = now
                    } else if now - alignmentStartTime! > 0.5 {
                        finalizeAlignment(using: imageAnchor)
                    }
                } else {
                    alignmentStartTime = nil
                }
            }
        }

        func extractYaw(from transform: simd_float4x4) -> Float {
            atan2(transform.columns.0.z, transform.columns.2.z)
        }

        func finalizeAlignment(using imageAnchor: ARImageAnchor) {
            guard let arView = arView,
                  let alignmentState = alignmentState else { return }

            alignmentState.alignmentComplete = true

            let anchorEntity = AnchorEntity(anchor: imageAnchor)
            arView.scene.addAnchor(anchorEntity)

            // Use marker as world origin
            worldRoot.position = .zero
            anchorEntity.addChild(worldRoot)
        }

        func startUpdateLoop() {
            guard let arView = arView else { return }

            updateCancellable = arView.scene.subscribe(
                to: SceneEvents.Update.self
            ) { [weak self] event in
                self?.updateMovement(deltaTime: Float(event.deltaTime))
            }
        }
        func updateMovement(deltaTime: Float) {
            guard controlState == .moving else { return }
            guard let character = character else { return }

            var transform = character.transform
            let worldDir = transform.rotation.act(moveDirection)
            transform.translation += worldDir * moveSpeed * deltaTime
            character.transform = transform
        }
        
        func startCameraSync() {
            guard let arView = arView else { return }

            cameraUpdateCancellable = arView.scene.subscribe(
                to: SceneEvents.Update.self
            ) { [weak self] _ in
                self?.syncCharacterRotationWithCamera()
            }
        }
        
        func syncCharacterRotationWithCamera() {
            guard
                let arView = arView,
                let character = character,
                isJumping == false
            else { return }

            let cameraTransform = arView.cameraTransform
            let forward = -cameraTransform.matrix.columns.2.xyz

            let horizontalForward = SIMD3<Float>(forward.x, 0, forward.z)
            if simd_length(horizontalForward) < 0.001 { return }

            let normalized = simd_normalize(horizontalForward)
            let yaw = atan2(normalized.x, normalized.z)

            character.transform.rotation =
                simd_quatf(angle: yaw, axis: [0, 1, 0])
        }
        
        @objc
        func handleTap(_ sender: UITapGestureRecognizer) {
            guard alignmentState?.alignmentComplete == true else { return }
            guard let arView = arView else { return }
            if podAnchor != nil { return }
            let location = sender.location(in: arView)

            // Raycast against existing horizontal planes
            let results = arView.raycast(from: location, allowing: .existingPlaneGeometry, alignment: .horizontal)
            guard let firstResult = results.first else { return }

            // Create an anchor at the raycast result and place the pod character there

            let anchor = AnchorEntity(raycastResult: firstResult)


            // Place character so feet rest on the plane (y ~ 0)
            let character = PodCharacter.make()
            character.position = [0.0, 0.0, 0.0]

            anchor.addChild(character)
            self.character = character
            arView.scene.addAnchor(anchor)
            self.podAnchor = anchor
            startCameraSync()
            startUpdateLoop()
        }


        // MARK: - Controls
        // MARK: - Movement tuning
        let baseStep: Float = 0.12 * 0.5   // ⬅️ half step
        let moveDuration: TimeInterval = 0.12
        
        private var movementTimer: Timer?
        func startMoving(_ action: @escaping () -> Void) {
            if isJumping { return }
            stopMoving()
            movementTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
                action()
            }
        }

        func stopMoving() {
            moveDirection = .zero
            if controlState == .moving {
                controlState = .idle
            }
        }
        func startMoveForward() {
            guard controlState != .jumping else { return }
            controlState = .moving
            moveDirection = [0, 0, 1]
        }

        func startMoveBackward() {
            guard controlState != .jumping else { return }
            controlState = .moving
            moveDirection = [0, 0, -1]
        }

        func startMoveLeft() {
            guard controlState != .jumping else { return }
            controlState = .moving
            moveDirection = [1, 0, 0]
        }

        func startMoveRight() {
            guard controlState != .jumping else { return }
            controlState = .moving
            moveDirection = [-1, 0, 0]
        }
        
        func moveLocal(by offset: SIMD3<Float>, duration: TimeInterval = 0.18) {
            guard let character = character else { return }
            var t = character.transform
            // Convert local-space offset to world-space using current rotation
            let worldOffset = t.rotation.act(offset)
            t.translation += worldOffset
            character.move(to: t, relativeTo: character.parent, duration: duration)
        }

        func moveForward() {
            moveLocal(by: [0, 0, -baseStep], duration: moveDuration)
        }

        func moveBackward() {
            moveLocal(by: [0, 0, baseStep], duration: moveDuration)
        }

        func moveLeft() {
            moveLocal(by: [-baseStep, 0, 0], duration: moveDuration)
        }

        func moveRight() {
            moveLocal(by: [baseStep, 0, 0], duration: moveDuration)
        }
        
        func jump() {
            guard let character = character else { return }
            guard controlState != .jumping else { return }

            // ⛔ stop movement immediately
            moveDirection = .zero
            controlState = .jumping
            isJumping = true

            let up: Float = 0.18

            var upTransform = character.transform
            upTransform.translation.y += up
            character.move(to: upTransform, relativeTo: character.parent, duration: 0.15)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                var downTransform = character.transform
                downTransform.translation.y -= up
                character.move(to: downTransform, relativeTo: character.parent, duration: 0.18)

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    self.isJumping = false
                    self.controlState = .idle   // ✅ unlock controls
                }
            }
        }


        func turnLeft() {
            guard let character = character else { return }
            let angle = Float.pi / 8
            character.transform.rotation *= simd_quatf(angle: angle, axis: [0, 1, 0])
        }

        func turnRight() {
            guard let character = character else { return }
            let angle = -Float.pi / 8
            character.transform.rotation *= simd_quatf(angle: angle, axis: [0, 1, 0])
        }
    }
}

#Preview {
    ContentView()
}

extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> {
        SIMD3(x, y, z)
    }
}
