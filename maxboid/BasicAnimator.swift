//
//  BasicAnimator.swift
//  maxboid
//
//  Created by Mark Dawson on 11/21/21.
//

import Foundation
import SceneKit

class BasicAnimator: NSObject {
  private let node = SCNNode()

  init(container: SCNNode) {
    container.addChildNode(node)
  }

  func start() {
    let a = CABasicAnimation(keyPath: "position.x")
    a.fromValue = 0.0
    a.toValue = 1.0
    a.duration = 0.5
    a.isRemovedOnCompletion = false
    a.fillMode = .forwards
    node.addAnimation(a, forKey: nil)
  }

  func startSpring() {
    let a = CASpringAnimation(keyPath: "position.x")
    a.fromValue = 0.0
    a.toValue = 1.0
    a.isRemovedOnCompletion = false
    a.fillMode = .forwards
    node.addAnimation(a, forKey: nil)
  }

  func dispose() {
    node.removeFromParentNode()
  }

  func currentValue() -> Float {
    return node.presentation.position.x
  }

}
