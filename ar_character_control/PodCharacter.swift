//
//  PodCharacter.swift
//  ar_character_control
//

import RealityKit
import UIKit

enum PodCharacter {
    static func make() -> ModelEntity {

        // Materials
        let bodyMaterial = SimpleMaterial(color: .init(red: 0.2, green: 0.6, blue: 0.95, alpha: 1.0), roughness: 0.3, isMetallic: true)

        // Approximate a capsule using a cylinder + two half-spheres
        let totalHeight: Float = 0.14
        let radius: Float = 0.035
        let sphereRadius: Float = radius
        let cylinderHeight: Float = totalHeight - (2.0 * sphereRadius)

        // Cylinder body
        let cylinderMesh = MeshResource.generateCylinder(height: cylinderHeight, radius: radius)
        let pod = ModelEntity(mesh: cylinderMesh, materials: [bodyMaterial])
        pod.position = [0.0,(cylinderHeight / 2.0), 0.0]


        // MARK: - Collision
        pod.generateCollisionShapes(recursive: false)

        // MARK: - Physics
        let physicsMaterial = PhysicsMaterialResource.generate(
            friction: 1.0,
            restitution: 0.4
        )

        pod.components[PhysicsBodyComponent.self] = PhysicsBodyComponent(
            massProperties: .default,
            material: physicsMaterial,
            mode: .dynamic
        )

        pod.components[PhysicsMotionComponent.self] = PhysicsMotionComponent(
            linearVelocity: .zero,
            angularVelocity: .zero
        )

        pod.components[PhysicsMotionComponent.self] =
            PhysicsMotionComponent(
                linearVelocity: .zero,
                angularVelocity: .zero
            )


        return pod
    }
}
