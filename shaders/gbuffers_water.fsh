#version 420

//--// Configuration //----------------------------------------------------------------------------------//

#include "/cfg/global.scfg"

//--// Outputs //----------------------------------------------------------------------------------------//

/* DRAWBUFFERS:2 */

layout (location = 0) out vec4 data0;

//--// Inputs //-----------------------------------------------------------------------------------------//

in vec4 tint;
in vec2 baseUV;

//--// Uniforms //---------------------------------------------------------------------------------------//

uniform sampler2D base;

//--// Functions //--------------------------------------------------------------------------------------//

void main() {
	data0 = texture(base, baseUV) * tint;
	if (data0.a == 0.0) discard;

	data0.rgb = pow(data0.rgb, vec3(GAMMA));
}
