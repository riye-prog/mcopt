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
} state;

layout(set = 0, binding = 2) uniform sampler2D texture0;
layout(set = 0, binding = 3) uniform sampler2D texture1;
layout(set = 0, binding = 4) uniform sampler2D texture2;
layout(location = 0) in vec4 color;
layout(location = 1) in vec2 tex0;
layout(location = 2) in vec2 tex1;
layout(location = 3) in vec2 tex2;
layout(location = 4) in float fogDistance;
layout(location = 5) in vec2 repeatUv;
layout(location = 6) flat in vec4 atlasBounds;
layout(location = 7) flat in uint surfaceFlags;
layout(location = 0) out vec4 fragmentColor;
layout(constant_id = 0) const uint features = 31u;

bool alphaPass(float value, uint function, float reference) {
    switch (function) {
        case 512u: return false;
        case 513u: return value < reference;
        case 514u: return value == reference;
        case 515u: return value <= reference;
        case 516u: return value > reference;
        case 517u: return value != reference;
        case 518u: return value >= reference;
        default: return true;
    }
}

void main() {
    vec4 result = color;
    if ((features & 1u) != 0u) {
        vec2 span = atlasBounds.zw - atlasBounds.xy;
        vec2 repeated = atlasBounds.xy + fract(repeatUv) * span;
        vec2 uv = span.x > 0.0 ? repeated : tex0;
        vec2 dx = span.x > 0.0 ? dFdxFine(repeatUv) * span : dFdxFine(tex0);
        vec2 dy = span.x > 0.0 ? dFdyFine(repeatUv) * span : dFdyFine(tex0);
        float detail = (surfaceFlags & 2u) != 0u ? 0.62 : 1.0;
        vec4 texel = textureGrad(texture0, uv, dx * detail, dy * detail);
        if ((surfaceFlags & 8u) != 0u && texel.a < 0.5) discard;
        if ((surfaceFlags & 2u) != 0u) texel.a = 1.0;
        result *= (state.flags.w & 2u) != 0u ? vec4(1, 1, 1, texel.a) : texel;
    }
    if ((features & 2u) != 0u) {
        vec4 overlay = texture(texture1, tex1);
        result.rgb = mix(overlay.rgb, result.rgb, overlay.a);
    }
    if ((features & 4u) != 0u) {
        result *= texture(texture2, tex2);
    }
    if ((features & 8u) != 0u && !alphaPass(result.a, state.flags.y, state.fog.w)) {
        discard;
    }
    if ((features & 16u) != 0u) {
        float density = state.fog.z * fogDistance;
        float factor = state.flags.z == 9729u
            ? clamp((state.fog.y - fogDistance) / max(0.00001, state.fog.y - state.fog.x), 0.0, 1.0)
            : exp(state.flags.z == 2048u ? -density : -density * density);
        result.rgb = mix(state.fogColor.rgb, result.rgb, factor);
    }
    fragmentColor = result;
}
