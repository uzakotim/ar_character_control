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
        config.planeDetection = [.horizontal, .vertical]
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
//        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
//        arView.addGestureRecognizer(tapGesture)

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
        
        // Physics + planes
        private var planeAnchorEntities: [UUID: AnchorEntity] = [:]
        private var planeModels: [UUID: ModelEntity] = [:]
        var ball: ModelEntity?
        var floorModel: ModelEntity?
        
        var cameraUpdateCancellable: Cancellable?
        var moveDirection = SIMD3<Float>.zero
        let moveSpeed: Float = 0.5   // meters per second (tune)
        private var updateCancellable: Cancellable?
        
        
        func spawnPod(at parent: Entity) {
            guard character == nil else { return }

            let pod = PodCharacter.make()

            guard let podModel = pod.firstModelEntity() else {
                fatalError("PodCharacter has no ModelEntity")
            }
            podModel.generateCollisionShapes(recursive: true)

            let material = PhysicsMaterialResource.generate(
                friction: 0.8,
                restitution: 0.6
            )

            // Ensure the pod can collide with dynamic bodies (like the ball)
            pod.generateCollisionShapes(recursive: true)
            let podMaterial = PhysicsMaterialResource.generate(
                friction: 0.8,
                restitution: 0.6
            )

            pod.components[PhysicsBodyComponent.self] = PhysicsBodyComponent(
                massProperties: PhysicsMassProperties(mass: 5.0),
                material: podMaterial,
                mode: .kinematic
            )

            pod.components[PhysicsMotionComponent.self] =
                PhysicsMotionComponent(linearVelocity: .zero, angularVelocity: .zero)

            // Place pod at marker origin
            pod.position = [0, 0, 0]
            
           
            
            parent.addChild(pod)

            self.character = pod

            startCameraSync()
            startUpdateLoop()
        }
        func spawnPodOnFloor(at worldRoot: Entity) {
            guard let arView = arView, character == nil else { return }

            let pod = PodCharacter.make()

            guard let podModel = pod.firstModelEntity() else {
                fatalError("PodCharacter has no ModelEntity")
            }
           
            podModel.generateCollisionShapes(recursive: true)

            let material = PhysicsMaterialResource.generate(
                friction: 0.8,
                restitution: 0.6
            )

            podModel.components[PhysicsBodyComponent.self] = PhysicsBodyComponent(
                massProperties: PhysicsMassProperties(mass: 5.0),
                material: material,
                mode: .kinematic
            )

            podModel.components[PhysicsMotionComponent.self] =
                PhysicsMotionComponent(linearVelocity: .zero, angularVelocity: .zero)

            // World position of marker origin
            let markerWorldPos = worldRoot.convert(position: .zero, to: nil)

            // Create a world-space raycast query straight down from the marker
            let rayOrigin = SIMD3<Float>(
                markerWorldPos.x,
                markerWorldPos.y + 0.045,   // small offset above marker
                markerWorldPos.z
            )
            let downDirection = SIMD3<Float>(0, -1, 0)
            let query = ARRaycastQuery(origin: rayOrigin,
                                       direction: downDirection,
                                       allowing: .existingPlaneGeometry,
                                       alignment: .horizontal)
            let rayResults = arView.session.raycast(query)
            if let hit = rayResults.first {
                let floorY = hit.worldTransform.columns.3.y

                // Convert world Y → local Y
                let localY = floorY - markerWorldPos.y
                pod.position = [0, localY, 0]
            } else {
                // Fallback: place slightly above marker
                pod.position = [0, 0.01, 0]
            }

            worldRoot.addChild(pod)
            pod.components[PhysicsMotionComponent.self] =
                PhysicsMotionComponent(linearVelocity: .zero, angularVelocity: .zero)
            character = pod

            startCameraSync()
            startUpdateLoop()
        }
        func spawnSoccerBall(near reference: Entity, in parent: Entity) {
            // Avoid duplicating the ball
            if ball != nil { return }

            let radius: Float = 0.025
            let sphere = MeshResource.generateSphere(radius: radius)
            let material = SimpleMaterial(color: .red, roughness: 0.3, isMetallic: false)
            let ballEntity = ModelEntity(mesh: sphere, materials: [material])

            // Collisions + dynamic physics
            ballEntity.generateCollisionShapes(recursive: false)

            // Use a higher restitution so it bounces more noticeably
            let physMaterial = PhysicsMaterialResource.generate(
                friction: 0.5,
                restitution: 0.95
            )
            let massProps = PhysicsMassProperties(
                shape: .generateSphere(radius: radius),
                mass: 0.25
            )
            ballEntity.components[PhysicsBodyComponent.self] = PhysicsBodyComponent(
                massProperties: massProps,
                material: physMaterial,
                mode: .dynamic
            )

            // Reduce damping so the ball doesn't lose all energy immediately
            if var body = ballEntity.components[PhysicsBodyComponent.self] as? PhysicsBodyComponent {
                body.linearDamping = 0.05
                body.angularDamping = 0.05
                ballEntity.components[PhysicsBodyComponent.self] = body
            }

            // Place in front of the reference entity (pod), slightly higher so it can drop and bounce
            let forwardDir = simd_normalize(reference.transform.rotation.act(SIMD3<Float>(0, 0, 1)))
            let spawnOffset: SIMD3<Float> = forwardDir * 0.25 + SIMD3<Float>(0, radius * 3.0, 0)
            ballEntity.position = reference.position + spawnOffset

            // 🔧 ADD motion component explicitly (CRITICAL)
            ballEntity.components[PhysicsMotionComponent.self] =
                PhysicsMotionComponent(linearVelocity: .zero, angularVelocity: .zero)

            // Give it a gentle initial kick and some spin
            var motion = ballEntity.components[PhysicsMotionComponent.self]!
            motion.linearVelocity = forwardDir * 0.6 + SIMD3<Float>(0, 0.2, 0)
            motion.angularVelocity = SIMD3<Float>(0, 6, 0)
            ballEntity.components[PhysicsMotionComponent.self] = motion


            parent.addChild(ballEntity)
            self.ball = ballEntity
        }
        
        func addStaticFloor(under reference: Entity, in parent: Entity) {
            if floorModel != nil { return }
            let size = SIMD3<Float>(2.0, 0.01, 2.0)
            let mesh = MeshResource.generateBox(size: size)
            let material = OcclusionMaterial()
            let floor = ModelEntity(mesh: mesh, materials: [material])
            floor.position = SIMD3<Float>(reference.position.x, reference.position.y - size.y * 0.5, reference.position.z)
            floor.generateCollisionShapes(recursive: false)
            let physMat = PhysicsMaterialResource.generate(friction: 0.9, restitution: 0.8)
            floor.components[PhysicsBodyComponent.self] = PhysicsBodyComponent(massProperties: .default, material: physMat, mode: .static)
            parent.addChild(floor)
            self.floorModel = floor
        }

        func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
            // Handle image anchor alignment until alignment completes
            if let arView = arView, let alignmentState = alignmentState, alignmentState.alignmentComplete == false {
                for anchor in anchors {
                    guard let imageAnchor = anchor as? ARImageAnchor else { continue }

                    alignmentState.isMarkerVisible = true

                    // Project marker into screen space
                    let worldPos = imageAnchor.transform.columns.3.xyz
                    guard let screenPos = arView.project(worldPos) else { continue }

                    let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
                    let distance = hypot(screenPos.x - center.x, screenPos.y - center.y)
                    alignmentState.screenDistance = distance

                    // Yaw-only error
                    let yaw = extractYaw(from: imageAnchor.transform)
                    alignmentState.yawError = abs(yaw)

                    let aligned = distance < 40 && alignmentState.yawError < 0.15
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

            // Always update colliders for any detected planes (horizontal + vertical)
            for a in anchors {
                if let plane = a as? ARPlaneAnchor {
                    addOrUpdatePlaneCollider(for: plane)
                }
            }
        }
        func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
            for a in anchors {
                guard let plane = a as? ARPlaneAnchor else { continue }
                addOrUpdatePlaneCollider(for: plane)
            }
        }

        func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
            guard let arView = arView else { return }
            for a in anchors {
                guard let plane = a as? ARPlaneAnchor else { continue }
                let id = plane.identifier
                if let anchorEnt = planeAnchorEntities[id] {
                    arView.scene.removeAnchor(anchorEnt)
                }
                planeAnchorEntities.removeValue(forKey: id)
                planeModels.removeValue(forKey: id)
            }
        }

        func extractYaw(from transform: simd_float4x4) -> Float {
            atan2(transform.columns.0.z, transform.columns.2.z)
        }

        func finalizeAlignment(using imageAnchor: ARImageAnchor) {
            guard let arView = arView,
                  let alignmentState = alignmentState else { return }

            alignmentState.alignmentComplete = true

            // Extract world transform ONCE
            let markerTransform = Transform(matrix: imageAnchor.transform)

            // Create a persistent world anchor
            let worldAnchor = AnchorEntity(world: markerTransform.translation)
            worldAnchor.transform.rotation = markerTransform.rotation

            arView.scene.addAnchor(worldAnchor)

            // Attach world root
            worldRoot.position = .zero
            worldAnchor.addChild(worldRoot)

            // Spawn pod on detected floor
            spawnPodOnFloor(at: worldRoot)
            if let pod = self.character {
                print("Added static floor and soccer ball near the pod")
                self.addStaticFloor(under: pod, in: self.worldRoot)
                self.spawnSoccerBall(near: pod, in: self.worldRoot)
            }

            // Safe to disable image detection now
            if let config = arView.session.configuration as? ARWorldTrackingConfiguration {
                config.detectionImages = []
                arView.session.run(config)
            }
        }


        private func addOrUpdatePlaneCollider(for plane: ARPlaneAnchor) {
            guard let arView = arView else { return }
            let id = plane.identifier

            let thickness: Float = 0.002

            // Compute size depending on plane alignment
            let size: SIMD3<Float>
            switch plane.alignment {
            case .horizontal:
                let width = max(plane.extent.x, 0.05)
                let length = max(plane.extent.z, 0.05)
                size = SIMD3<Float>(width, thickness, length)
            case .vertical:
                let width = max(plane.extent.x, 0.05)
                let height = max(plane.extent.y, 0.05)
                size = SIMD3<Float>(width, height, thickness)
            @unknown default:
                let width = max(plane.extent.x, 0.05)
                let length = max(plane.extent.z, 0.05)
                size = SIMD3<Float>(width, thickness, length)
            }

            let mesh = MeshResource.generateBox(size: size)
            let material = OcclusionMaterial()

            if let model = planeModels[id], let anchorEnt = planeAnchorEntities[id] {
                // Update existing
                model.model = ModelComponent(mesh: mesh, materials: [material])
                model.position = SIMD3<Float>(plane.center.x, plane.center.y, plane.center.z)
                if model.components[PhysicsBodyComponent.self] == nil {
                    model.generateCollisionShapes(recursive: false)
                    let physMat = PhysicsMaterialResource.generate(friction: 0.9, restitution: 0.9)
                    model.components[PhysicsBodyComponent.self] = PhysicsBodyComponent(massProperties: .default, material: physMat, mode: .static)
                }
                if anchorEnt.scene == nil {
                    arView.scene.addAnchor(anchorEnt)
                }
            } else {
                // Create new anchor + model
                let anchorEnt = AnchorEntity(anchor: plane)
                let model = ModelEntity(mesh: mesh, materials: [material])
                model.position = SIMD3<Float>(plane.center.x, plane.center.y, plane.center.z)
                model.generateCollisionShapes(recursive: false)
                let physMat = PhysicsMaterialResource.generate(friction: 0.9, restitution: 0.9)
                model.components[PhysicsBodyComponent.self] = PhysicsBodyComponent(massProperties: .default, material: physMat, mode: .static)

                anchorEnt.addChild(model)
                arView.scene.addAnchor(anchorEnt)

                planeAnchorEntities[id] = anchorEnt
                planeModels[id] = model
            }
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

            guard let model = character?.firstModelEntity(),
                  var motion = model.components[PhysicsMotionComponent.self]
            else { return }

            let worldDir = character!.transform.rotation.act(moveDirection)

            motion.linearVelocity.x = worldDir.x * moveSpeed
            motion.linearVelocity.z = worldDir.z * moveSpeed

            model.components[PhysicsMotionComponent.self] = motion

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
            if var motion = character?.components[PhysicsMotionComponent.self] {
                motion.linearVelocity = .zero
                character?.components[PhysicsMotionComponent.self] = motion
            }
            controlState = .idle
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
        
//        func moveLocal(by offset: SIMD3<Float>, duration: TimeInterval = 0.18) {
//            guard let character = character else { return }
//            var t = character.transform
//            // Convert local-space offset to world-space using current rotation
//            let worldOffset = t.rotation.act(offset)
//            t.translation += worldOffset
//            character.move(to: t, relativeTo: character.parent, duration: duration)
//        }
//
//        func moveForward() {
//            moveLocal(by: [0, 0, -baseStep], duration: moveDuration)
//        }
//
//        func moveBackward() {
//            moveLocal(by: [0, 0, baseStep], duration: moveDuration)
//        }
//
//        func moveLeft() {
//            moveLocal(by: [-baseStep, 0, 0], duration: moveDuration)
//        }
//
//        func moveRight() {
//            moveLocal(by: [baseStep, 0, 0], duration: moveDuration)
//        }
        
        func jump() {
            guard let model = character?.firstModelEntity(),
                  var motion = model.components[PhysicsMotionComponent.self]
            else { return }

            controlState = .jumping
            isJumping = true

            // upward impulse
            motion.linearVelocity.y = 1.8
            model.components[PhysicsMotionComponent.self] = motion

            // gravity-like fall
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                guard var motion = model.components[PhysicsMotionComponent.self] else { return }
                motion.linearVelocity.y = -1.8
                model.components[PhysicsMotionComponent.self] = motion

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    motion.linearVelocity.y = 0
                    model.components[PhysicsMotionComponent.self] = motion
                    self.isJumping = false
                    self.controlState = .idle
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

extension Entity {
    func firstModelEntity() -> ModelEntity? {
        if let model = self as? ModelEntity {
            return model
        }
        for child in children {
            if let found = child.firstModelEntity() {
                return found
            }
        }
        return nil
    }
}

