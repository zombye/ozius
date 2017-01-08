#version 400

//--// Outputs //----------------------------------------------------------------------------------------//

/* DRAWBUFFERS: */

layout (location = 0) out vec4 data0;
layout (location = 1) out vec4 data1;

//--// Inputs //-----------------------------------------------------------------------------------------//

in vec4 tint;
in vec2 texCoord;

//--// Uniforms //---------------------------------------------------------------------------------------//

uniform sampler2D albedo;

//--// Functions //--------------------------------------------------------------------------------------//

void main() {
	discard;
}
