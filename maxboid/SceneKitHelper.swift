//
//  SceneKitHelper.swift
//  maxboid
//
//  Created by Mark Dawson on 11/19/21.
//

import Foundation
import SceneKit

final class SceneKitHelper {

  /// Takes a SCNGeometry instance and copies the vertices and indices count times.
  ///  SCNGeometry is always a fixed size, so scale is used to change the size of the duplicated geometry
  static func duplicateGeometry(_ geometry: SCNGeometry, count: Int, scales: [Float]) -> SCNGeometry? {
    guard let vertexSource = geometry.sources(for: .vertex).first else {
      return nil
    }
    let vertices = vertexSource.data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> [Float] in
      guard let baseAddress = ptr.baseAddress?.assumingMemoryBound(to: Float.self) else {
        return []
      }
      return Array<Float>(UnsafeBufferPointer(start: baseAddress, count: vertexSource.data.count / MemoryLayout<Float>.size))
    }

    guard let normalSource = geometry.sources(for: .normal).first else {
      return nil
    }
    let normals = normalSource.data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> [Float] in
      guard let baseAddress = ptr.baseAddress?.assumingMemoryBound(to: Float.self) else {
        return []
      }
      return Array<Float>(UnsafeBufferPointer(start: baseAddress, count: normalSource.data.count / MemoryLayout<Float>.size))
    }

    guard let sourceElement = geometry.elements.first else {
      return nil
    }

    // IMPORTANT! The size of the items in the element buffer can be different depending on the complexity
    // of the scenekit geometry. Below we are using UInt8 but you should check
    // sourceElement.bytesPerIndex to see what has been stored in the buffer and put in the appropriate
    // type below
    let indices = sourceElement.data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> [UInt8] in
      guard let baseAddress = ptr.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
        return []
      }
      return Array<UInt8>(UnsafeBufferPointer(start: baseAddress, count: sourceElement.data.count / MemoryLayout<UInt8>.size))
    }

    var geometryIndices = ContiguousArray<Float>()
    var duplicateVertices = ContiguousArray<Float>()
    var duplicateNormals = ContiguousArray<Float>()
    var duplicateIndices = [Int32]()
    for instanceIndex in 0..<count {

      // Copy across all of the vertices
      for i in 0..<vertices.count {
        duplicateVertices.append(vertices[i] * scales[instanceIndex])
      }

      for i in 0..<normals.count {
        duplicateNormals.append(normals[i])
      }

      // For the indices we need to increment the values to take into account
      // the duplicated geometry
      for i in 0..<indices.count {
        duplicateIndices.append(Int32(indices[i]) + Int32(instanceIndex) * Int32(vertexSource.vectorCount))
      }

      // Each vertices has an associated geometry instance index associated with it.
      // This lets the shader grab per geometry information from other buffers
      for _ in 0..<vertexSource.vectorCount {
        geometryIndices.append(Float(instanceIndex))
      }
    }

    let duplicateVerticesData = duplicateVertices.withUnsafeBufferPointer { ptr in
      return Data(buffer: ptr)
    }

    let duplicateVertexSource = SCNGeometrySource(
      data: duplicateVerticesData,
      semantic: .vertex,
      vectorCount: vertexSource.vectorCount * count,
      usesFloatComponents: true,
      componentsPerVector: vertexSource.componentsPerVector,
      bytesPerComponent: vertexSource.bytesPerComponent,
      dataOffset: vertexSource.dataOffset,
      dataStride: vertexSource.dataStride
    )

    let duplicateNormalsData = duplicateNormals.withUnsafeBufferPointer { ptr in
      return Data(buffer: ptr)
    }

    let duplicateNormalsSource = SCNGeometrySource(
      data: duplicateNormalsData,
      semantic: .normal,
      vectorCount: normalSource.vectorCount * count,
      usesFloatComponents: true,
      componentsPerVector: normalSource.componentsPerVector,
      bytesPerComponent: normalSource.bytesPerComponent,
      dataOffset: normalSource.dataOffset,
      dataStride: normalSource.dataStride
    )

    let geometryIndicesData = geometryIndices.withUnsafeBytes { ptr in
      return Data(ptr)
    }

    //todo: we can get rid of this
    let geometryIndicesSource = SCNGeometrySource(
      data: geometryIndicesData,
      semantic: .color,
      vectorCount: geometryIndices.count,
      usesFloatComponents: true,
      componentsPerVector: 1,
      bytesPerComponent: MemoryLayout<Float>.size,
      dataOffset: 0,
      dataStride: MemoryLayout<Float>.stride
    )

    let element = SCNGeometryElement(indices: duplicateIndices, primitiveType: .triangles)
    return SCNGeometry(sources: [duplicateVertexSource, duplicateNormalsSource, geometryIndicesSource], elements: [element])
  }
}
