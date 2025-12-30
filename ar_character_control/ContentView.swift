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

    func up() { coordinator?.moveForward() }
    func down() { coordinator?.moveBackward() }
    func left() { coordinator?.moveLeft() }
    func right() { coordinator?.moveRight() }
    func jump() { coordinator?.jump() }
}

struct ContentView : View {
    @StateObject private var controls = ControlsProxy()

    var body: some View {
        ZStack {
            ARViewContainer(controls: controls)
                .edgesIgnoringSafeArea(.all)

            // Overlay controls
            VStack {
                Spacer()
                HStack {
                    // Bottom-left D-pad
                    VStack(spacing: 8) {
                        HStack { Spacer() }
                        Button(action: { controls.up() }) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(.white)
                                .shadow(radius: 2)
                        }
                        HStack(spacing: 16) {
                            Button(action: { controls.left() }) {
                                Image(systemName: "arrow.left.circle.fill")
                                    .font(.system(size: 44))
                                    .foregroundStyle(.white)
                                    .shadow(radius: 2)
                            }
                            Button(action: { controls.down() }) {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.system(size: 44))
                                    .foregroundStyle(.white)
                                    .shadow(radius: 2)
                            }
                            Button(action: { controls.right() }) {
                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.system(size: 44))
                                    .foregroundStyle(.white)
                                    .shadow(radius: 2)
                            }
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

struct ARViewContainer: UIViewRepresentable {
    let controls: ControlsProxy

    func makeCoordinator() -> Coordinator {
        let c = Coordinator()
        return c
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)

        // Configure AR session for horizontal plane detection
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        config.environmentTexturing = .automatic
        arView.session.run(config)

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

    class Coordinator: NSObject {
        weak var arView: ARView?
        var podAnchor: AnchorEntity?
        var character: Entity?
        var isJumping = false

        @objc
        func handleTap(_ sender: UITapGestureRecognizer) {
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
        }


        // MARK: - Controls

        func moveLocal(by offset: SIMD3<Float>, duration: TimeInterval = 0.18) {
            guard let character = character else { return }
            var t = character.transform
            // Convert local-space offset to world-space using current rotation
            let worldOffset = t.rotation.act(offset)
            t.translation += worldOffset
            character.move(to: t, relativeTo: character.parent, duration: duration)
        }

        func moveForward() {
            let distance: Float = 0.12
            moveLocal(by: [0, 0, -distance], duration: 0.18)
        }

        func moveBackward() {
            let distance: Float = 0.12
            moveLocal(by: [0, 0, distance], duration: 0.18)
        }

        func moveLeft() {
            let distance: Float = 0.12
            moveLocal(by: [-distance,0,0], duration: 0.18)
        }
        func moveRight() {
            let distance: Float = 0.12
            moveLocal(by: [distance,0,0], duration: 0.18)
        }
        
        func jump() {
            guard let character = character, !isJumping else { return }
            isJumping = true

            let jumpHeight: Float = 0.18
            let groundY = character.transform.translation.y

            var up = character.transform
            up.translation.y = groundY + jumpHeight

            character.move(to: up, relativeTo: character.parent, duration: 0.15)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.33) {
                guard let character = self.character else { return }
                var down = character.transform
                down.translation.y = groundY
                character.move(to: down, relativeTo: character.parent, duration: 0.18)
                self.isJumping = false
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

