#version 420 compatibility

//--// Structs //----------------------------------------------------------------------------------------//

struct worldStruct {
	vec3 globalLightVector;
	vec3 globalLightColor;
};

//--// Outputs //----------------------------------------------------------------------------------------//

out vec3 positionView, positionLocal;

out mat3 tbnMatrix;
out vec4 tint;
out vec2 baseUV, lmUV;
out float blockID;

out worldStruct world;

//--// Inputs //-----------------------------------------------------------------------------------------//

layout (location = 0)  in vec4 vertexPosition;
layout (location = 2)  in vec3 vertexNormal;
layout (location = 3)  in vec4 vertexColor;
layout (location = 8)  in vec2 vertexUV;
layout (location = 9)  in vec2 vertexLightmap;
layout (location = 10) in vec4 vertexMetadata;
layout (location = 12) in vec4 vertexTangent;

//--// Uniforms //---------------------------------------------------------------------------------------//

uniform float sunAngle;

uniform vec3 shadowLightPosition;

uniform mat4 gbufferProjection, gbufferModelViewInverse;

//--// Functions //--------------------------------------------------------------------------------------//

#include "/lib/illuminance.glsl"

//--//

#include "/lib/gbuffers/initPosition.vsh"

mat3 calculateTBN() {
	vec3 tangent = normalize(vertexTangent.xyz);

	return mat3(
		gl_NormalMatrix * tangent,
		gl_NormalMatrix * cross(tangent, vertexNormal) * sign(vertexTangent.w),
		gl_NormalMatrix * vertexNormal
	);
}

void main() {
	gl_Position = initPosition();
	positionView  = gl_Position.xyz;
	positionLocal = (gbufferModelViewInverse * gl_Position).xyz;
	gl_Position = gbufferProjection * gl_Position;

	tbnMatrix = calculateTBN();
	tint      = vertexColor;
	baseUV    = vertexUV;
	lmUV      = vertexLightmap / 256.0;
	blockID   = vertexMetadata.x;

	//--// Fill world struct

	world.globalLightVector = normalize(shadowLightPosition);
	world.globalLightColor  = mix(vec3(0.2), vec3(ILLUMINANCE_SUN), sunAngle < 0.5);
}
