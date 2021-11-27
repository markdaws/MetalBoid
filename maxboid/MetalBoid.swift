//
//  MetalBoid.swift
//  maxboid
//
//  Created by Mark Dawson on 11/16/21.
//

import Foundation
import Metal
import UIKit
import MetalKit
import SceneKit

final class MetalBoid {

  let numBoid: Int
  var posBuffer1: MTLBuffer?
  var velBuffer1: MTLBuffer?
  let mtlDevice: MTLDevice

  private var cmdQueue: MTLCommandQueue?
  private var positionPS: MTLComputePipelineState?
  private var posBuffer0: MTLBuffer?
  private var velBuffer0: MTLBuffer?
  private var flockPosition: SIMD3<Float> = [0, 0, 0]

  init?(numBoid: Int) {
    guard let device = MTLCreateSystemDefaultDevice() else {
      return nil
    }

    self.numBoid = numBoid
    mtlDevice = device

    guard let defaultLibrary = mtlDevice.makeDefaultLibrary() else {
      return nil
    }

    guard let positionFunc = defaultLibrary.makeFunction(name: "stepBoid") else {
      return nil
    }
    guard let pipelineStatePos = try? mtlDevice.makeComputePipelineState(function: positionFunc) else {
      return nil
    }
    positionPS = pipelineStatePos

    cmdQueue = mtlDevice.makeCommandQueue()
  }

  func makeBufferShared(length: Int) -> MTLBuffer? {
    return mtlDevice.makeBuffer(length: length, options: .storageModeShared)
  }

  func generateRandomPositions(
    count: Int,
    xRange: ClosedRange<Float>,
    yRange: ClosedRange<Float>,
    zRange: ClosedRange<Float>
  ) -> MTLBuffer? {
    var positions = ContiguousArray<SIMD3<Float>>(repeating: [0,0,0], count: count)
    for i in 0..<count {
      positions[i] = [Float.random(in: xRange), Float.random(in: yRange), Float.random(in: zRange)]
    }

    let buffer = positions.withUnsafeBytes { ptr -> MTLBuffer? in
      guard let baseAddr = ptr.baseAddress else {
        return nil
      }
      return mtlDevice.makeBuffer(bytes: baseAddr, length: ptr.count, options: .storageModeShared)
    }
    return buffer
  }

  func generateRandomVelocities(count: Int) -> MTLBuffer? {
    var velocities = ContiguousArray<SIMD3<Float>>(repeating: [0,0,0], count: count)

    for i in 0..<count {
      let vel: SIMD3<Float> = normalize([Float.random(in: -1...1), Float.random(in: -1...1), Float.random(in: -1...1)])
      velocities[i] = vel
    }

    let buffer = velocities.withUnsafeBytes { ptr -> MTLBuffer? in
      guard let baseAddr = ptr.baseAddress else {
        return nil
      }
      return mtlDevice.makeBuffer(bytes: baseAddr, length: ptr.count, options: .storageModeShared)
    }
    return buffer
  }

  func swapBuffers() {
    let tempPos = posBuffer0
    posBuffer0 = posBuffer1
    posBuffer1 = tempPos

    let tempVel = velBuffer0
    velBuffer0 = velBuffer1
    velBuffer1 = tempVel
  }

  func setBuffers(pos: MTLBuffer, vel: MTLBuffer) {
    posBuffer0 = pos
    posBuffer1 = makeBufferShared(length: pos.length)
    velBuffer0 = vel
    velBuffer1 = makeBufferShared(length: vel.length)
  }

  /// Steps the boids position and velocities and waits for the compute shader to complete
  /// and return before returning.
  func stepBoidSync(uniform: Uniform, forces: ContiguousArray<Force>) {
    guard let cmdQueue = cmdQueue,
          let posPipelineState = positionPS,
          let posBuffer0 = posBuffer0,
          let velBuffer0 = velBuffer0 else {
      return
    }

    // An array of forces applied to the boid. Even if we have 0 we just create a buffer
    // of length 1
    let forceBuffer = makeBufferShared(length: MemoryLayout<Force>.stride * max(1, forces.count))!
    var ptr = forceBuffer.contents().bindMemory(to: Force.self, capacity: forces.count)
    for f in forces {
      ptr.pointee = f
      ptr = ptr.advanced(by: 1)
    }

    guard let uniformBuffer = uniform.toBuffer(device: mtlDevice) else { return }
    guard let cmdBuffer = cmdQueue.makeCommandBuffer() else { return }
    guard let cmdEncoder = cmdBuffer.makeComputeCommandEncoder() else { return }
    cmdEncoder.setComputePipelineState(posPipelineState)
    cmdEncoder.setBuffer(posBuffer0, offset: 0, index: 0)
    cmdEncoder.setBuffer(velBuffer0, offset: 0, index: 1)
    cmdEncoder.setBuffer(forceBuffer, offset: 0, index: 2)
    cmdEncoder.setBuffer(posBuffer1, offset: 0, index: 3)
    cmdEncoder.setBuffer(velBuffer1, offset: 0, index: 4)
    cmdEncoder.setBuffer(uniformBuffer, offset: 0, index: 5)

    let gridSize = MTLSize(width: numBoid, height: 1, depth: 1)
    // This can vary based on the complexity of the
    var threadgroupSize = posPipelineState.maxTotalThreadsPerThreadgroup
    if threadgroupSize > numBoid {
      threadgroupSize = numBoid
    }
    let finalSize = MTLSize(width: threadgroupSize, height: 1, depth: 1)

    cmdEncoder.dispatchThreads(gridSize, threadsPerThreadgroup: finalSize)
    cmdEncoder.endEncoding()
    cmdBuffer.commit()
    cmdBuffer.waitUntilCompleted()
  }

}
