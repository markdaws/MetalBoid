//
//  Uniforms.swift
//  maxboid
//
//  Created by Mark Dawson on 11/26/21.
//

import Foundation
import Metal
import simd

/// Contains values that are passed through to the shaders
/// NOTE: We can't use SceneKit types like SCNVector3 and SCNMatrix4 here
/// they don't transfer well to the shaders
struct Uniform {
  /// The number of boid to render - this cannot be changed after initialization
  var numBoid: Float

  /// The number of forces (Attractors/repellors) that are in the scene
  var numForces: Float

  /// The radius where any boid withing this distance will have an effect on the
  /// target boid
  var neighbourRadius: Float
  var neighbourRadiusSq: Float

  /// A weighting to apply to the alignment rule. Higher values mean the boid will
  /// prioritize flying in the same orientation over cohesion or separation.
  var alignmentWeight: Float

  /// A weight to how important it is for the boid to move away from close neighbours
  var separationWeight: Float

  /// A weight specifying how important it is for boid to try to stay close to their average
  /// neighbour position
  var cohesionWeight: Float

  /// The time since the last update e.g. 0.16ms
  var deltaTime: Float

  /// The x bounds of the world, centered around 0, so roughly -xBounds<=xBoid<=xBounds
  var xBounds: Float
  var yBounds: Float
  var zBounds: Float

  /// The importance of keeping the boid inside the specified bounds. A higher number means the boid will turn back
  /// quicker to go back inside the bounds.
  var boundsWeight: Float

  /// How fast the boids are moving
  var boidSpeed: Float

  /// How jittery the boids are. A low value means they will turn quickly to match their updated velocity, a higher value
  /// means they maintain more of their current velocity. Between 0 and 1, 0 means immediately update vecocity to new
  /// velocity, 1 means the velocity is never updated always keeps the first velocity, probably somewhere around 0.7 is good
  var reactionFactor: Float

  var showPointLight: Float

  /// A local model transofmr applied to each boid e.g. rotation
  var modelTransform: simd_float4x4

  func toBuffer(device: MTLDevice) -> MTLBuffer? {
    guard let buffer = device.makeBuffer(length: MemoryLayout<Uniform>.stride, options: []) else {
      return nil
    }

    let contents = buffer.contents().bindMemory(to: Uniform.self, capacity: 1)
    contents.pointee.numBoid = numBoid
    contents.pointee.numForces = numForces
    contents.pointee.neighbourRadius = neighbourRadius
    contents.pointee.neighbourRadiusSq = neighbourRadiusSq
    contents.pointee.alignmentWeight = alignmentWeight
    contents.pointee.separationWeight = separationWeight
    contents.pointee.cohesionWeight = cohesionWeight
    contents.pointee.deltaTime = deltaTime
    contents.pointee.xBounds = xBounds
    contents.pointee.yBounds = yBounds
    contents.pointee.zBounds = zBounds
    contents.pointee.boundsWeight = boundsWeight
    contents.pointee.boidSpeed = boidSpeed
    contents.pointee.reactionFactor = reactionFactor
    contents.pointee.showPointLight = showPointLight
    contents.pointee.modelTransform = modelTransform
    return buffer
  }
}
