//
//  Force.swift
//  maxboid
//
//  Created by Mark Dawson on 11/25/21.
//

import Foundation

struct Force {
  var radius: Float
  var strength: Float
  /// required because float3 in metal align on 16 byte boundaries
  var padding: SIMD2<Float>
  var pos: SIMD3<Float>
}
