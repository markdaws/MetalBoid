//
//  RandomWalker.swift
//  maxboid
//
//  Created by Mark Dawson on 11/19/21.
//

import Foundation
import SceneKit

final class RandomWalker {
  var position: SIMD3<Float> = [0, 0, 0]
  var velocity: SIMD3<Float>
  private var startPosition: SIMD4<Float> = [0, 0, 0, 0]
  private let xBounds: ClosedRange<Float>
  private let yBounds: ClosedRange<Float>
  private let zBounds: ClosedRange<Float>
  private let speed: Float

  init(
    speed: Float,
    startPosition: SIMD3<Float>,
    xBounds: ClosedRange<Float>,
    yBounds: ClosedRange<Float>,
    zBounds: ClosedRange<Float>
  ) {
    self.speed = speed
    self.xBounds = xBounds
    self.yBounds = yBounds
    self.zBounds = zBounds
    self.position = startPosition
    self.startPosition = SIMD4<Float>(startPosition.x, startPosition.y, startPosition.z, 1.0)
    velocity = normalize(SIMD3<Float>(Float.random(in: -1...1), Float.random(in: -1...1), Float.random(in: -1...1)))
  }

  func update() -> SIMD3<Float> {
    updateRnd()
    return position
  }

  func updateRnd() {
    var v = SIMD3<Float>(Float.random(in: -1...1), Float.random(in: -1...1), Float.random(in: -1...1))
    v = normalize(v) * 1.0
    velocity = simd_mix(velocity + v, velocity, [0.1, 0.1, 0.1])
    position += velocity * speed

    if position.x < xBounds.lowerBound {
      velocity.x = 5
    } else if position.x > xBounds.upperBound {
      velocity.x = -5
    } else if position.y < yBounds.lowerBound {
      velocity.y = 5
    } else if position.y > yBounds.upperBound {
      velocity.y = -5
    } else if position.z < zBounds.lowerBound {
      velocity.z = 5
    } else if position.z > zBounds.upperBound {
      velocity.z = -5
    }
  }

}

