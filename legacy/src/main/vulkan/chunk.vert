#version 450
layout(set = 0, binding = 0, std140) uniform DrawState {
    mat4 mvp;
    mat4 model;
    mat4 textures[3];
    vec4 color;
    vec4 fogColor;
    vec4 fog;
    vec4 light0;
    vec4 light1;
    vec4 ambient;
    vec4 coordinates[3];
    uvec4 flags;
    ivec4 attributes[6];
    vec4 normal;
} state;

layout(set = 0, binding = 1, std430) readonly buffer Vertices {
    uint words[];
};
struct ChunkUnit {
    vec3 translation;
    uint first;
    uint count;
};
layout(set = 0, binding = 10, std430) readonly buffer Units {
    ChunkUnit units[];
};

layout(location = 0) out vec4 color;
layout(location = 1) out vec2 tex0;
layout(location = 2) out vec2 tex1;
layout(location = 3) out vec2 tex2;
layout(location = 4) out float fogDistance;
layout(location = 5) out vec2 repeatUv;
layout(location = 6) flat out vec4 atlasBounds;
layout(location = 7) flat out uint surfaceFlags;

void main() {
    ChunkUnit unit = units[gl_InstanceIndex];
    if (gl_VertexIndex >= unit.count) {
        gl_Position = vec4(0, 0, -1, 1);
        return;
    }
    uint base = (unit.first + uint(gl_VertexIndex)) * 8u;
    vec4 position = vec4(vec3(uintBitsToFloat(words[base]), uintBitsToFloat(words[base + 1u]),
        uintBitsToFloat(words[base + 2u])) + unit.translation, 1);
    gl_Position = state.mvp * position;
    gl_Position.y = -gl_Position.y;
    gl_Position.z = (gl_Position.z + gl_Position.w) * 0.5;
    fogDistance = abs((state.model * position).z);
    color = unpackUnorm4x8(words[base + 3u]);
    uint u = words[base + 4u];
    uint v = words[base + 5u];
    uint repeat = words[base + 7u];
    surfaceFlags = repeat >> 16u;
    atlasBounds = vec4(0);
    repeatUv = vec2(0);
    tex0 = vec2(0);
    if ((repeat & 0x10000u) != 0u) {
        atlasBounds = vec4(unpackUnorm2x16(u), unpackUnorm2x16(v));
        repeatUv = vec2(repeat & 255u, (repeat >> 8u) & 255u);
    } else {
        vec4 projected = state.textures[0] * vec4(uintBitsToFloat(u), uintBitsToFloat(v), 0, 1);
        tex0 = projected.xy / projected.w;
    }
    uint light = words[base + 6u];
    vec2 lightUv = vec2(bitfieldExtract(int(light), 0, 16), bitfieldExtract(int(light), 16, 16));
    tex1 = (state.textures[1] * vec4(state.coordinates[1].xyz, 1)).xy;
    tex2 = (state.textures[2] * vec4(lightUv, 0, 1)).xy;
    if ((state.flags.w & 256u) != 0u) tex0.y = 1.0 - tex0.y;
    if ((state.flags.w & 512u) != 0u) tex1.y = 1.0 - tex1.y;
    if ((state.flags.w & 1024u) != 0u) tex2.y = 1.0 - tex2.y;
}
