//
//  PodCharacter.swift
//  ar_character_control
//
//  Created by Timur Uzakov on 30/12/25.
//

import RealityKit
internal import UIKit

enum PodCharacter {
    static func make() -> Entity {
        let root = Entity()

        // Materials
        let bodyMaterial = SimpleMaterial(color: .init(red: 0.2, green: 0.6, blue: 0.95, alpha: 1.0), roughness: 0.3, isMetallic: true)
        let headMaterial = SimpleMaterial(color: .white, roughness: 0.2, isMetallic: false)

        // Approximate a capsule using a cylinder + two half-spheres
        let totalHeight: Float = 0.14
        let radius: Float = 0.035
        let sphereRadius: Float = radius
        let cylinderHeight: Float = totalHeight - (2.0 * sphereRadius)

        // Cylinder body
        let cylinderMesh = MeshResource.generateCylinder(height: cylinderHeight, radius: radius)
        let cylinder = ModelEntity(mesh: cylinderMesh, materials: [bodyMaterial])
        cylinder.position = [0.0, sphereRadius + (cylinderHeight / 2.0), 0.0]

        // Top hemisphere (use a sphere and clip visually by scaling Y to 0.5)
        let hemiMesh = MeshResource.generateSphere(radius: sphereRadius)
        let topHemisphere = ModelEntity(mesh: hemiMesh, materials: [bodyMaterial])
        topHemisphere.scale = [1.0, 0.5, 1.0]
        topHemisphere.position = [0.0, sphereRadius + cylinderHeight + (sphereRadius * 0.5), 0.0]

        // Bottom hemisphere
        let bottomHemisphere = ModelEntity(mesh: hemiMesh, materials: [bodyMaterial])
        bottomHemisphere.scale = [1.0, 0.5, 1.0]
        bottomHemisphere.position = [0.0, sphereRadius * 0.5, 0.0]

        // Head: a sphere sitting on top of the capsule
        let headRadius: Float = 0.03
        let headMesh = MeshResource.generateSphere(radius: headRadius)
        let head = ModelEntity(mesh: headMesh, materials: [headMaterial])
        head.position = [0.0, totalHeight + headRadius, 0.0]

        // Optional: tiny feet as half-spheres
        let footRadius: Float = 0.018
        let footMesh = MeshResource.generateSphere(radius: footRadius)
        let leftFoot = ModelEntity(mesh: footMesh, materials: [bodyMaterial])
        let rightFoot = ModelEntity(mesh: footMesh, materials: [bodyMaterial])
        leftFoot.scale = [1.0, 0.5, 1.0]
        rightFoot.scale = [1.0, 0.5, 1.0]
        leftFoot.position = [-0.02, footRadius, 0.02]
        rightFoot.position = [0.02, footRadius, 0.02]

        root.addChild(cylinder)
        root.addChild(topHemisphere)
        root.addChild(bottomHemisphere)
        root.addChild(head)
        root.addChild(leftFoot)
        root.addChild(rightFoot)

        // Enable collisions and kinematic physics so dynamic bodies (like the ball) can bounce off the pod.
        root.generateCollisionShapes(recursive: true)
        let podPhysicsMaterial = PhysicsMaterialResource.generate(friction: 0.8, restitution: 0.3)
        root.components[PhysicsBodyComponent.self] = PhysicsBodyComponent(
            massProperties: .default,
            material: podPhysicsMaterial,
            mode: .kinematic
        )

        return root
    }
}
