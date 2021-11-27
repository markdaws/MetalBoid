//
//  GameViewController.swift
//  maxboid
//
//  Created by Mark Dawson on 11/14/21.
//

import UIKit
import QuartzCore
import SceneKit

final class GameViewController: UIViewController {

  private var mtlBoid: MetalBoid?
  private var boidMaterial = SCNMaterial()
  private var lastRenderTime: Double?
  private var pauseBoids = false
  private var uniformBuffers: BufferManager?
  private var speedAnimator: BasicAnimator?
  private let scene = SCNScene()
  private var forces = ContiguousArray<Force>()
  private var forceAnimators = [ForceInfo]()

  private struct ForceInfo {
    var force: Force
    let randomWalker: RandomWalker
    let debugNode: SCNNode
  }

  private enum ForceModes {
    case none
    case singleAttractor
    case singleRepellor
    case mixed
  }
  private var forceMode = ForceModes.none

  /// Any boid inside this distance from another boid will be considered when calculating the
  /// vector forces for a boid
  private let neighbourRadius: Float = 1.5
  private let numBoid = 8000
  private var showPointLight = false

  /// NOTE: These values have been tweaked to make the scene look good on a landscape
  /// iPhone screen. You will need to play with the values to make it look good in other
  /// scenarios. Also changing a value will require modifying other values, for example if
  /// you make the boid move really fast you may have to increase the cohesion factor or
  /// bounds weight for example. Basically it's a process of trial and error until you get
  /// something that looks good to you.
  lazy var defaultUniform = Uniform(
    numBoid: Float(numBoid),
    numForces: 0,
    neighbourRadius: neighbourRadius,
    neighbourRadiusSq: neighbourRadius * neighbourRadius,
    alignmentWeight: 2.0,
    separationWeight: 2.0,
    cohesionWeight: 4.0,
    deltaTime: 0.0,
    xBounds: 15.0,
    yBounds: 6.0,
    zBounds: 1.5,
    boundsWeight: 2.0,
    boidSpeed: 100.0,
    reactionFactor: 0.9,
    showPointLight: 0.0,
    modelTransform: simd_float4x4.init(diagonal: [1.0,1.0,1.0,1.0])
  )

  override func viewDidLoad() {
    super.viewDidLoad()

    initBoid(numBoid: numBoid)
    createScene(numBoid: numBoid)

    if let mtlDevice = mtlBoid?.mtlDevice {
      uniformBuffers = BufferManager(device: mtlDevice, inflightCount: 3, createBuffer: { mtlDevice in
        return mtlDevice.makeBuffer(length: MemoryLayout<Uniform>.stride, options: [])
      })
      uniformBuffers?.createBuffers()
    }

    let tapGesture = UITapGestureRecognizer(target: self, action: #selector(onTap))
    view.addGestureRecognizer(tapGesture)
  }

  private func initBoid(numBoid: Int) {
    mtlBoid = MetalBoid(numBoid: numBoid)

    // Fill the initial buffers with random positions + velocities
    let posBuffer0 = mtlBoid?.generateRandomPositions(
      count: numBoid,
      xRange: -2.5...2.5,
      yRange: -2.5...2.5,
      zRange: -2.5...2.5
    )
    let velBuffer0 = mtlBoid?.generateRandomVelocities(count: numBoid)

    guard let posBuffer0 = posBuffer0,
          let velBuffer0 = velBuffer0 else {
      return
    }

    mtlBoid?.setBuffers(pos: posBuffer0, vel: velBuffer0)
  }

  private func createScene(numBoid: Int) {
    let cameraNode = SCNNode()
    let camera = SCNCamera()
    cameraNode.camera = camera
    camera.fieldOfView = 60
    scene.rootNode.addChildNode(cameraNode)
    cameraNode.position = SCNVector3(x: 0, y: 0, z: 15)

    let lightNode = SCNNode()
    lightNode.light = SCNLight()
    lightNode.light!.type = .omni
    lightNode.position = SCNVector3(x: 0, y: 10, z: 10)
    scene.rootNode.addChildNode(lightNode)

    let ambientLightNode = SCNNode()
    ambientLightNode.light = SCNLight()
    ambientLightNode.light!.type = .ambient
    ambientLightNode.light!.color = UIColor.darkGray
    scene.rootNode.addChildNode(ambientLightNode)

    let scnView = self.view as! SCNView
    scnView.scene = scene
    scnView.allowsCameraControl = true
    scnView.showsStatistics = false
    scnView.backgroundColor = UIColor.black
    scnView.rendersContinuously = true
    scnView.delegate = self

    addBoidGeometry()
  }

  private func addBoidGeometry() {
    guard let mtlBoid = mtlBoid else {
      return
    }

    // To render a boid we use a model stores in models.scn
    let boidNode = SCNScene(named: "art.scnassets/models.scn")!.rootNode.childNode(withName: "boid", recursively: true)!
    let boidGeometry = boidNode.geometry!

    // Apply some random scaling factor to each boid to make them different sizes, looks a bit
    // more interesting
    var scales = [Float](repeating: 1.0, count: numBoid)
    scales = scales.map({ val in
      return val * Float.random(in: 0.5...1.5)
    })

    // Take the boid geometry and duplicate it numBoid times
    let duplicatedBoids = SceneKitHelper.duplicateGeometry(boidGeometry, count: numBoid, scales: scales)!

    // Apply our custom shaders to the boid material, this lets us pass the position and velocity
    // buffers through to our metal shaders
    let program = SCNProgram()
    program.fragmentFunctionName = "boidFragment"
    program.vertexFunctionName = "boidVertex"
    boidMaterial.program = program
    boidMaterial.setValue(mtlBoid.posBuffer1, forKey: "inPos")
    boidMaterial.setValue(mtlBoid.velBuffer1, forKey: "inVel")
    duplicatedBoids.firstMaterial = boidMaterial

    scene.rootNode.addChildNode(SCNNode(geometry: duplicatedBoids))
  }

  @objc func onTap(_ recognizer: UITapGestureRecognizer) {

    switch forceMode {
      case .none:
        forceMode = .singleAttractor
      case .singleAttractor:
        forceMode = .singleRepellor
      case .singleRepellor:
        forceMode = .mixed
      case .mixed:
        forceMode = .none
    }

    addForces()
  }

  private func addForces() {
    removeForces()

    showPointLight = false
    switch forceMode {
      case .none:
        return
      case .singleAttractor:
        forces.append(Force(
          radius: 5.0,
          strength: 3,
          padding: [0.0, 0.0],
          pos: [0,0,0]
        ))
        showPointLight = true
      case .singleRepellor:
        forces.append(Force(
          radius: 2.0,
          strength: -150,
          padding: [0.0, 0.0],
          pos: [10,0,0]
        ))
      case .mixed:
        forces.append(contentsOf: [
          Force(
            radius: 2.0,
            strength: -150,
            padding: [0.0, 0.0],
            pos: [-10.0, 0.0, 0.0]
          ),
          Force(
            radius: 5.0,
            strength: 10,
            padding: [0.0, 0.0],
            pos: [0,0,0]
          ),
          Force(
            radius: 2.0,
            strength: -150,
            padding: [0.0, 0.0],
            pos: [10,0,0]
          )
        ])
        showPointLight = true
    }

    for force in forces {
      let walker = RandomWalker(
        speed: force.strength > 0 ? 0.00 : 0.02,
        startPosition: force.pos,
        xBounds: -defaultUniform.xBounds...defaultUniform.xBounds,
        yBounds: -defaultUniform.yBounds...defaultUniform.yBounds,
        zBounds: -defaultUniform.zBounds...defaultUniform.zBounds
      )

      let forceNode = createForceDebugNode(force: force)
      forceNode.simdPosition = walker.position
      scene.rootNode.addChildNode(forceNode)
      forceAnimators.append(ForceInfo(force: force, randomWalker: walker, debugNode: forceNode))
    }

  }

  private func createForceDebugNode(force: Force) -> SCNNode {
    let sphere = SCNSphere(radius: CGFloat(force.radius) * 0.5)
    let mat = SCNMaterial()
    mat.lightingModel = .lambert
    mat.diffuse.contents = force.strength > 0 ? UIColor.white : UIColor.red
    if force.strength > 0 {
      mat.emission.contents = UIColor.white
    }
    sphere.firstMaterial = mat

    let node = SCNNode(geometry: sphere)
    return node
  }

  private func removeForces() {
    forces.removeAll()
    for animator in forceAnimators {
      animator.debugNode.removeFromParentNode()
    }
    forceAnimators.removeAll()
  }

  private func updateForces() {
    for i in 0..<forceAnimators.count {
      let info = forceAnimators[i]
      let newPos = info.randomWalker.update()
      info.debugNode.simdPosition = newPos
      forces[i].pos = newPos
    }
  }
}

extension GameViewController: SCNSceneRendererDelegate {

  func renderer(_ renderer: SCNSceneRenderer, willRenderScene scene: SCNScene, atTime time: TimeInterval) {
    if pauseBoids {
      return
    }

    guard let mtlBoid = mtlBoid,
          let uniformBuffer = uniformBuffers?.nextSync() else {
      return
    }

    guard let lastRenderTime = lastRenderTime else {
      lastRenderTime = time
      return
    }

    // Put a min here just incase the app was paused since the last update, we don't want
    // a huge delta time that will cause the boid to render really far away
    let deltaTime = min(0.5, Float(time - lastRenderTime))
    self.lastRenderTime = time

    var uniform = uniformBuffer.contents().bindMemory(to: Uniform.self, capacity: 1).pointee
    uniform.numBoid = defaultUniform.numBoid
    uniform.numForces = defaultUniform.numForces
    uniform.neighbourRadius = defaultUniform.neighbourRadius
    uniform.neighbourRadiusSq = defaultUniform.neighbourRadiusSq
    uniform.alignmentWeight = defaultUniform.alignmentWeight
    uniform.separationWeight = defaultUniform.separationWeight
    uniform.cohesionWeight = defaultUniform.cohesionWeight
    uniform.deltaTime = defaultUniform.deltaTime
    uniform.xBounds = defaultUniform.xBounds
    uniform.yBounds = defaultUniform.yBounds
    uniform.zBounds = defaultUniform.zBounds
    uniform.boundsWeight = defaultUniform.boundsWeight
    uniform.boidSpeed = defaultUniform.boidSpeed
    uniform.modelTransform = defaultUniform.modelTransform
    uniform.reactionFactor = defaultUniform.reactionFactor
    uniform.deltaTime = deltaTime
    uniform.showPointLight = showPointLight ? 1.0 : 0.0

    if let speedAnimator = speedAnimator {
      let speed = (1.0 - speedAnimator.currentValue())
      uniform.boidSpeed = 7.0 * speed
      uniform.modelTransform = simd_float4x4(SCNMatrix4MakeRotation(Float.pi * 2.0 / Float(deltaTime) * 0.5, 0, 1, 0))
    } else {
      uniform.boidSpeed = 7.0
      uniform.modelTransform = simd_float4x4(diagonal: [1.0, 1.0, 1.0, 1.0])
    }

    updateForces()
    uniform.numForces = Float(forces.count)

    // When we step the posBuffer0 and velBuffer0 are used to update posBuffer1
    // and velBuffer1
    mtlBoid.stepBoidSync(uniform: uniform, forces: forces)
    boidMaterial.setValue(mtlBoid.posBuffer1, forKey: "inPos")
    boidMaterial.setValue(mtlBoid.velBuffer1, forKey: "inVel")
    boidMaterial.setValue(uniform.toBuffer(device:mtlBoid.mtlDevice), forKey: "uniform")

    uniformBuffers?.release()

    // After updating the material we can now swap posBuffer0 = posBuffer1 and
    // velBuffer0 to be velBuffer1 and repeat the next cycle
    mtlBoid.swapBuffers()
  }
}
