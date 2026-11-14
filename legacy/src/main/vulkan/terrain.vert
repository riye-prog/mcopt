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

layout(push_constant) uniform Geometry {
    vec4 translation;
    uint stride;
} geometry;

layout(location = 0) out vec4 color;
layout(location = 1) out vec2 tex0;
layout(location = 2) out vec2 tex1;
layout(location = 3) out vec2 tex2;
layout(location = 4) out float fogDistance;

uint bits(uint offset, uint count) {
    return bitfieldExtract(words[offset >> 2], int((offset & 3u) * 8u), int(count));
}

int signedBits(uint offset, uint count) {
    return bitfieldExtract(int(words[offset >> 2]), int((offset & 3u) * 8u), int(count));
}

vec4 readAttribute(uint base, ivec4 layoutInfo, vec4 fallback, bool normalized) {
    if (layoutInfo.x < 0) {
        return fallback;
    }
    uint offset = base + uint(layoutInfo.x);
    for (int index = 0; index < layoutInfo.z; index++) {
        uint component = uint(index);
        switch (layoutInfo.y) {
            case 5126:
                fallback[index] = uintBitsToFloat(words[(offset >> 2) + component]);
                break;
            case 5121:
                fallback[index] = float(bits(offset + component, 8)) / (normalized ? 255.0 : 1.0);
                break;
            case 5120:
                fallback[index] = max(-1.0, float(signedBits(offset + component, 8)) / (normalized ? 127.0 : 1.0));
                break;
            case 5122:
                fallback[index] = float(signedBits(offset + component * 2u, 16)) / (normalized ? 32767.0 : 1.0);
                break;
            case 5123:
                fallback[index] = float(bits(offset + component * 2u, 16)) / (normalized ? 65535.0 : 1.0);
                break;
            case 5124:
                fallback[index] = float(int(words[(offset >> 2) + component]));
                break;
            default:
                fallback[index] = float(words[(offset >> 2) + component]);
        }
    }
    return fallback;
}

void main() {
    uint base = uint(gl_VertexIndex) * geometry.stride;
    vec4 position = readAttribute(base, state.attributes[0], vec4(0, 0, 0, 1), false);
    position.xyz += geometry.translation.xyz;
    gl_Position = state.mvp * position;
    gl_Position.y = -gl_Position.y;
    gl_Position.z = (gl_Position.z + gl_Position.w) * 0.5;
    gl_PointSize = 1.0;
    vec4 eye = state.model * position;
    color = readAttribute(base, state.attributes[1], state.color, true);
    if ((state.flags.w & 1u) != 0u) {
        vec3 normal = normalize((state.model * vec4(readAttribute(base, state.attributes[5], state.normal, true).xyz, 0)).xyz);
        float light0 = max(0, dot(normal, normalize(state.light0.xyz))) * state.light0.w;
        float light1 = max(0, dot(normal, normalize(state.light1.xyz))) * state.light1.w;
        color.rgb *= min(vec3(1), state.ambient.rgb + light0 + light1);
    }
    vec4 uv = readAttribute(base, state.attributes[2], state.coordinates[0], false);
    if ((state.flags.w & 4u) != 0u) {
        uv = eye;
    }
    vec4 projected = state.textures[0] * vec4(uv.xyz, 1);
    tex0 = projected.xy / projected.w;
    tex1 = (state.textures[1] * vec4(readAttribute(base, state.attributes[3], state.coordinates[1], false).xyz, 1)).xy;
    tex2 = (state.textures[2] * vec4(readAttribute(base, state.attributes[4], state.coordinates[2], false).xyz, 1)).xy;
    if ((state.flags.w & 256u) != 0u) tex0.y = 1.0 - tex0.y;
    if ((state.flags.w & 512u) != 0u) tex1.y = 1.0 - tex1.y;
    if ((state.flags.w & 1024u) != 0u) tex2.y = 1.0 - tex2.y;
    fogDistance = abs(eye.z);
}
