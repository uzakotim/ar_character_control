//
//  ContentView.swift
//  ar_character_control
//
//  Created by Timur Uzakov on 30/12/25.
//

import SwiftUI
import RealityKit
import ARKit

struct ContentView : View {
    var body: some View {
        ARViewContainer()
            .edgesIgnoringSafeArea(.all)
    }
}

struct ARViewContainer: UIViewRepresentable {

    func makeCoordinator() -> Coordinator {
        Coordinator()
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

            let character = PodCharacter.make()
            // Place character so feet rest on the plane (y ~ 0)
            character.position = [0.0, 0.0, 0.0]

            anchor.addChild(character)
            arView.scene.addAnchor(anchor)
            self.podAnchor = anchor
        }
    }
}

#Preview {
    ContentView()
}

