//
//  PodCharacter.swift
//  ar_character_control
//

import RealityKit
import UIKit

enum PodCharacter {

    static func make() -> ModelEntity {

        // MARK: - Dimensions
        let height: Float = 0.14
        let radius: Float = 0.035

        // MARK: - Mesh
        let mesh = MeshResource.generateCylinder(
            height: height,
            radius: radius
        )

        // MARK: - Material (blue)
        let material = SimpleMaterial(
            color: UIColor(
                red: 0.2,
                green: 0.6,
                blue: 0.95,
                alpha: 1.0
            ),
            roughness: 0.3,
            isMetallic: true
        )

        // MARK: - ModelEntity (SINGLE BODY)
        let pod = ModelEntity(
            mesh: mesh,
            materials: [material]
        )

        // Move pivot so bottom sits on the floor
        pod.position.y = height / 2

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
