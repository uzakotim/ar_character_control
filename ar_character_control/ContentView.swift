//
//  ContentView.swift
//  ar_character_control
//
//  Created by Timur Uzakov on 30/12/25.
//

import SwiftUI
import RealityKit

struct ContentView : View {
    var body: some View {
        RealityView { content in

            let character = PodCharacter.make()
            // Place character so feet rest on the plane (y ~ 0)
            character.position = [0.0, 0.0, 0.0]

            // Create horizontal plane anchor for the content
            let anchor = AnchorEntity(.plane(.horizontal, classification: .any, minimumBounds: SIMD2<Float>(0.2, 0.2)))
            anchor.addChild(character)

            // Add the horizontal plane anchor to the scene
            content.add(anchor)

            content.camera = .spatialTracking

        }
        .edgesIgnoringSafeArea(.all)
    }

}

#Preview {
    ContentView()
}

