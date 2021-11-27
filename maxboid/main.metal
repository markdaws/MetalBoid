//
//  main.metal
//  maxboid
//
//  Created by Mark Dawson on 11/14/21.
//

#include <metal_stdlib>
using namespace metal;
#include <SceneKit/scn_metal>

typedef struct {
  float3 position [[ attribute(SCNVertexSemanticPosition) ]];
  float3 normal [[ attribute(SCNVertexSemanticNormal) ]];
  float boidIndex [[ attribute(SCNVertexSemanticColor) ]];
} VertexIn;

typedef struct {
  float boidIndex;
  float3 normal;
  float4 position [[position]];
  float3 positionWorld;
} VertexOut;

struct Uniforms {
  float numBoid;
  float numForces;
  float neighbourRadius;
  float neighbourRadiusSq;
  float alignmentWeight;
  float separationWeight;
  float cohesionWeight;
  float deltaTime;
  float xBounds;
  float yBounds;
  float zBounds;
  float boundsWeight;
  float boidSpeed;
  float reactionFactor;
  float showPointLight;
  float4x4 modelTransform;
};

struct Force {
  float radius;
  float strength;
  // NOTE: We have this because float3 is aligned on 16 bytes
  float2 padding;
  packed_float3 pos;
};

struct AmbientLight {
  half3 color;
  float intensity;
};

struct PointLight {
  float3 position;
  half3 color;
  float intensity;
  float attenuationConstant;
  float attenuationLinear;
  float attenuationExp;

  float attenuation(float lightDist) {
    return attenuationConstant + attenuationLinear * lightDist + attenuationExp * lightDist * lightDist;
  }
};

/// Pick a color from the palette
half3 colorFromPalette1(uint seed) {
  int idx = seed - 5.0 * floor(float(seed) / 5.0);
  half3 palette[5] = {
    half3(0.9, 0.22, 0.27),
    half3(0.66, 0.85, 0.86),
    half3(0.27, 0.48, 0.62),
    half3(0.11, 0.21, 0.34),
    half3(0.95, 0.98, 0.93)
  };
  return palette[idx];
}

/// Rotates v1 to v2
// https://gist.github.com/kevinmoran/b45980723e53edeb8a5a43c49f134724
float3x3 rotateTo(float3 v1, float3 v2) {
  float3 crossAxis = cross( v1, v2 );

  const float cosA = dot( v1, v2 );
  const float k = 1.0f / ( 1.0f + cosA );

  return float3x3((crossAxis.x * crossAxis.x * k) + cosA,
                  (crossAxis.y * crossAxis.x * k) - crossAxis.z,
                  (crossAxis.z * crossAxis.x * k) + crossAxis.y,
                  (crossAxis.x * crossAxis.y * k) + crossAxis.z,
                  (crossAxis.y * crossAxis.y * k) + cosA,
                  (crossAxis.z * crossAxis.y * k) - crossAxis.x,
                  (crossAxis.x * crossAxis.z * k) - crossAxis.y,
                  (crossAxis.y * crossAxis.z * k) + crossAxis.x,
                  (crossAxis.z * crossAxis.z * k) + cosA );
}

fragment half4 boidFragment(VertexOut in [[stage_in]],
                            device const Uniforms& uniform [[ buffer(1) ]],
                            texture2d<float, access::sample> diffuseTexture [[texture(0)]]) {

  half3 objectColor = pow(colorFromPalette1(uint(in.boidIndex)), 2.2);

  if (uniform.showPointLight != 1.0) {
    return half4(objectColor, 1.0);
  }

  AmbientLight ambientLight = { .color = half3(1.0), .intensity = 0.4 };
  PointLight pointLight = {
    .position = float3(0.0, 0.0, 0.0),
    .color = half3(1.0, 1.0, 1.0),
    .intensity = 5.5,
    .attenuationConstant = 0.0,
    .attenuationLinear = 0.1,
    .attenuationExp = 0.1
  };

  float lightDist = length(in.positionWorld - pointLight.position);
  float3 lightDir = normalize(in.positionWorld - pointLight.position);
  float intensity = saturate(dot(in.normal, lightDir));

  float attenuation = pointLight.attenuation(lightDist);
  half3 ambient = ambientLight.color * ambientLight.intensity;
  half3 point = intensity * pointLight.color * pointLight.intensity * 1.0 / attenuation;

  return half4(objectColor * (ambient + point), 1.0);
}

/// inPos is an array of x,y,z values for the position of the boid
/// inVel is an array of x,y,z with the velocity of the boid
vertex VertexOut boidVertex(VertexIn in [[ stage_in]],
                            constant SCNSceneBuffer& scn_frame [[buffer(0)]],
                            device const float* inPos [[ buffer(1) ]],
                            device const float* inVel [[ buffer(2) ]]) {

  VertexOut vOut;

  // Each vertex in the boid geometry has an associated boidIndex attribute
  // which can then be used to pick out the velocity and position of the boid
  int boidIndex = in.boidIndex * 3;
  float3 boidVel = float3(inVel[boidIndex], inVel[boidIndex+1], inVel[boidIndex+2]);
  float3 boidPos = float3(inPos[boidIndex], inPos[boidIndex+1], inPos[boidIndex+2]);

  // Rotate the geometry to point towards the direction of travel
  float3x3 r = rotateTo(float3(0,1,0), boidVel);
  float4 vertexPos = float4(in.position * r, 1.0) + float4(boidPos, 0.0);

  vOut.position = scn_frame.projectionTransform * scn_frame.viewTransform * vertexPos;
  vOut.positionWorld = vertexPos.xyz;
  vOut.boidIndex = in.boidIndex;
  vOut.normal = (scn_frame.inverseViewTransform * float4(in.normal, 0.0)).xyz;
  return vOut;
}

kernel void stepBoid(device const packed_float3* inPos [[ buffer(0) ]],
                     device const packed_float3* inVel [[ buffer(1) ]],
                     device const Force* inForces [[ buffer(2) ]],
                     device packed_float3* outPos [[ buffer(3) ]],
                     device packed_float3* outVel [[ buffer(4) ]],
                     device const Uniforms& uniforms [[ buffer(5) ]],
                     uint index [[thread_position_in_grid]])
{
  float3 separation = float3(0.0, 0.0, 0.0);
  float3 alignment = float3(0.0, 0.0, 0.0);
  float3 cohesion = float3(0.0, 0.0, 0.0);
  float3 bounds = float3(0.0, 0.0, 0.0);

  int neighbourCount = 0;

  float3 boidPos = (uniforms.modelTransform * float4(inPos[index], 1.0)).xyz;
  float3 boidVel = inVel[index];

  // If the boid is currently outside of the target bounds we apply a
  // force to make it move back inside the bounds. Changing the value
  // of bounds weight to a larger value will make the boid turn back
  // faster inside the bounds
  if (boidPos.x > uniforms.xBounds) {
    bounds.x = -uniforms.boundsWeight;
  } else if (boidPos.x < -uniforms.xBounds) {
    bounds.x = uniforms.boundsWeight;
  } else if (boidPos.y > uniforms.yBounds) {
    bounds.y = -uniforms.boundsWeight;
  } else if (boidPos.y < -uniforms.yBounds) {
    bounds.y = uniforms.boundsWeight;
  } else if (boidPos.z > uniforms.zBounds) {
    bounds.z = -uniforms.boundsWeight;
  } else if (boidPos.z < -uniforms.zBounds) {
    bounds.z = uniforms.boundsWeight;
  }

  for(uint i=0; i<uint(uniforms.numBoid); ++i) {
    if (i != index) {
      float3 neighbourPos = inPos[i];

      float3 neighbourDiff = boidPos - neighbourPos;
      float neighbourLength = length(neighbourDiff);
      if (neighbourLength < uniforms.neighbourRadius) {
        separation += (1.0 - saturate(neighbourLength / uniforms.neighbourRadius)) * normalize(neighbourDiff);

        float3 neighbourVel = inVel[i];
        alignment += normalize(neighbourVel);
        cohesion += neighbourPos;
        neighbourCount += 1;
      }
    }
  }

  if(neighbourCount > 0) {
    float avg = 1.0 / neighbourCount;
    alignment *= avg;
    cohesion *= avg;
  }

  // Add a vector that moves the boid towards the center of its neighbours
  cohesion = normalize(cohesion - boidPos);

  float3 forces = float3(0.0);
  for (uint i=0; i<uniforms.numForces; ++i) {
    Force force = inForces[i];
    float3 diff = force.pos - boidPos;
    float diffLength = length(diff);
    if (diffLength < 5) {
      forces += normalize(diff) * force.strength;
    }
  }

  float3 vel = uniforms.alignmentWeight * alignment +
               uniforms.separationWeight * separation +
               uniforms.cohesionWeight * cohesion +
               forces + bounds;

  // Don't snap to the target vector straight away, gradually move towards to
  // reduce sudden swerves
  vel = normalize(mix(normalize(vel), boidVel, uniforms.reactionFactor));

  float3 newPos = boidPos + vel * uniforms.deltaTime * uniforms.boidSpeed;

  outPos[index] = newPos;
  outVel[index] = uniforms.boidSpeed == 0.0 ? boidVel : vel;
}
