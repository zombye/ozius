#version 420

//--// Configuration //----------------------------------------------------------------------------------//

#include "/cfg/global.scfg"

#define RAYTRACE_SAMPLES 1 // [1 2 4 8 16]

//--// Misc

const float sunPathRotation = -40.0;

//--// Texture formats
/*
const int colortex0Format = RGBA32F; // Material
const int colortex1Format = RGBA32F; // Normals, lightmap
const int colortex2Format = RGBA32F; // Transparent surfaces
const int colortex3Format = RGBA32F; // Current frame
const int colortex4Format = RGBA32F; // Previous frame
*/

const bool colortex4Clear = false;

//--// Structs //----------------------------------------------------------------------------------------//

struct materialStruct {
	vec3 diffuse;  // RGB of base texture.
	vec3 specular; // RGB of specular texture.
	vec3 emission; // A of specular texture, currently same color as diffuse.
};
const materialStruct emptyMaterial = materialStruct(vec3(0.0), vec3(0.0), vec3(0.0));

struct surfaceStruct {
	materialStruct material;

	vec3 normal;
	vec3 normalGeom;

	vec2 depth; // y is linearized

	vec3 positionScreen; // Position in screen-space
	vec3 positionView;   // Position in view-space
	vec3 positionLocal;  // Position in local-space
};

struct lightStruct {
	vec2 engine;
	float pss;

	vec3 global;
	vec3 sky;
	vec3 block;
};

//--// Outputs //----------------------------------------------------------------------------------------//

/* DRAWBUFFERS:34 */

layout (location = 0) out vec3 composite;
layout (location = 1) out vec3 prevComposite;

//--// Inputs //-----------------------------------------------------------------------------------------//

in vec2 fragCoord;

//--// Uniforms //---------------------------------------------------------------------------------------//

uniform int frameCounter;

uniform float viewWidth, viewHeight;

//--//

uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;

uniform mat4 gbufferProjection, gbufferModelView;
uniform mat4 gbufferPreviousProjection, gbufferPreviousModelView;
uniform mat4 gbufferProjectionInverse, gbufferModelViewInverse;

//--//

uniform sampler2D colortex0, colortex1;
uniform sampler2D colortex4;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;

//--// Functions //--------------------------------------------------------------------------------------//

#include "/lib/preprocess.glsl"

#include "/lib/util/packing/normal.glsl"

#include "/lib/util/hammersley.glsl"

//--//

#include "/lib/composite/get/material.fsh"
#include "/lib/composite/get/normal.fsh"

//--//

float linearizeDepth(float depth) {
	return -1.0 / ((depth * 2.0 - 1.0) * gbufferProjectionInverse[2].w + gbufferProjectionInverse[3].w);
}
vec3 screenSpaceToViewSpace(vec3 screenSpace) {
	vec4 viewSpace = gbufferProjectionInverse * vec4(screenSpace * 2.0 - 1.0, 1.0);
	return viewSpace.xyz / viewSpace.w;
}
vec3 viewSpaceToLocalSpace(vec3 viewSpace) {
	return (gbufferModelViewInverse * vec4(viewSpace, 1.0)).xyz;
}
vec3 viewSpaceToScreenSpace(vec3 viewSpace) {
	vec4 screenSpace = gbufferProjection * vec4(viewSpace, 1.0);
	return (screenSpace.xyz / screenSpace.w) * 0.5 + 0.5;
}

//--//

vec3 getTemporalNoiseVector(vec2 coord, uint curSample) {
	coord += hammersley((frameCounter % 100) * RAYTRACE_SAMPLES + curSample, 100 * RAYTRACE_SAMPLES);

	vec4 nv = vec4(
		fract(sin(dot(coord - 1, vec2(12.9898, 78.233))) * 43758.5453),
		fract(sin(dot(coord, vec2(12.9898, 78.233))) * 43758.5453),
		fract(sin(dot(coord + 1, vec2(12.9898, 78.233))) * 43758.5453),
		fract(sin(dot(coord + 2, vec2(12.9898, 78.233))) * 43758.5453)
	);

	return normalize(nv.xyz * 2.0 - 1.0) * (nv.w * 0.5 + 0.5);
}

//--//

bool raytraceIntersection(vec3 pos, vec3 vec, out vec3 screenSpace, out vec3 viewSpace) {
	const float maxSteps  = 32;
	const float stepSize  = 0.125;
	const float stepScale = 1.6;

	pos = pos + (vec * stepSize);

	for (uint i = 0; i < maxSteps; i++) {
		viewSpace   = pos + (vec * pow(i, stepScale) * stepSize);
		screenSpace = viewSpaceToScreenSpace(viewSpace);

		if (any(greaterThan(abs(screenSpace - 0.5), vec3(0.5)))) return false;

		float screenZ = texture(depthtex1, screenSpace.xy).r;
		float diff    = viewSpace.z - linearizeDepth(screenZ);

		if (diff <= 0.0) {
			// Get the info required to accurately intersect a plane
			vec3 samplePos  = screenSpaceToViewSpace(vec3(screenSpace.xy, screenZ));
			vec3 sampleNorm = getNormalGeom(screenSpace.xy);

			// Accurately intersect the plane we think is the right one
			viewSpace  += vec * (dot(samplePos - viewSpace, sampleNorm) / dot(vec, sampleNorm));
			screenSpace = viewSpaceToScreenSpace(viewSpace);

			// Check to make sure we've actually hit something
			// TODO: Also check to make sure we at least got close enough that it's still believable that we actually hit the plane we think we hit.
			if (any(greaterThan(abs(screenSpace - 0.5), vec3(0.5))) || texture(depthtex1, screenSpace.xy).r == 1.0) return false;

			return true;
		}
	}

	return false;
}

vec3 raytrace(surfaceStruct surface) {
	vec3 result = surface.material.emission;

	for (uint i = 0; i < RAYTRACE_SAMPLES; i++) {
		vec3 diffuse = surface.material.diffuse;
		vec3 hitCoord;
		vec3 hitPos;

		vec3 vector = getTemporalNoiseVector(fragCoord, i);
		if (dot(vector, surface.normal) < 0) vector = -vector;

		materialStruct hitMaterial;
		if (raytraceIntersection(surface.positionView, vector, hitCoord, hitPos)) {
			hitMaterial = getMaterial(hitCoord.st);
		} else {
			hitMaterial = emptyMaterial;
		}

		result += diffuse * hitMaterial.emission;
		diffuse *= hitMaterial.diffuse;
	}
	result /= RAYTRACE_SAMPLES;

	return result;
}

//--//

vec3 getPreviousFrame(vec3 positionLocal) {
	mat4 previousMVP = gbufferPreviousProjection * gbufferPreviousModelView;
	vec4 previousSSP = previousMVP * vec4((positionLocal + cameraPosition) - previousCameraPosition, 1.0); previousSSP /= previousSSP.w;

	return texture(colortex4, previousSSP.xy * 0.5 + 0.5).rgb;
}

//--//

void main() {
	surfaceStruct surface;

	surface.depth.x = texture(depthtex1, fragCoord).r;
	if (surface.depth.x == 1.0) return;

	surface.positionScreen = vec3(fragCoord, surface.depth.x);
	surface.positionView   = screenSpaceToViewSpace(surface.positionScreen);
	surface.positionLocal  = viewSpaceToLocalSpace(surface.positionView);

	surface.depth.y = surface.positionView.z;

	surface.material = getMaterial(fragCoord);

	surface.normal     = getNormal(fragCoord);
	surface.normalGeom = getNormalGeom(fragCoord);

	vec3 currFrame = raytrace(surface);
	vec3 prevFrame = getPreviousFrame(surface.positionLocal);
	
	composite = mix(currFrame, prevFrame, 0.95);
	prevComposite = composite;
}
