#include <metal_stdlib>
using namespace metal;
struct DirectUniforms {
    float4x4 mvp, model, textureMatrices[3];
    float4 color, fogColor, fog, light0, light1, ambient, coordinates[3];
    uint4 flags;
    int4 attributes[6];
    float4 normal;
};
struct DirectOutput {
    float4 position [[position]];
    float4 color;
    float2 uv0, uv1, uv2;
    float fogDistance;
};
float4 attribute(device const uchar *data, int4 layout, float4 fallback, bool normalized) {
    if (layout.x < 0)
        return fallback;
    device const uchar *p = data + layout.x;
    float4 result = fallback;
    for (int i = 0; i < layout.z; i++) {
        if (layout.y == 5126)
            result[i] = as_type<float>(*reinterpret_cast<device const uint *>(p + i * 4));
        else if (layout.y == 5121)
            result[i] = float(p[i]) / (normalized ? 255.0 : 1.0);
        else if (layout.y == 5120)
            result[i] =
                max(-1.0, float(*reinterpret_cast<device const char *>(p + i)) / (normalized ? 127.0 : 1.0));
        else if (layout.y == 5122)
            result[i] =
                float(*reinterpret_cast<device const short *>(p + i * 2)) / (normalized ? 32767.0 : 1.0);
        else if (layout.y == 5123)
            result[i] =
                float(*reinterpret_cast<device const ushort *>(p + i * 2)) / (normalized ? 65535.0 : 1.0);
        else if (layout.y == 5124)
            result[i] = float(*reinterpret_cast<device const int *>(p + i * 4));
        else
            result[i] = float(*reinterpret_cast<device const uint *>(p + i * 4));
    }
    return result;
}
DirectOutput transformVertex(device const uchar *data, constant DirectUniforms &u, float3 translation) {
    float4 p = attribute(data, u.attributes[0], float4(0, 0, 0, 1), false);
    p.xyz += translation;
    DirectOutput out;
    out.position = u.mvp * p;
    out.position.y = -out.position.y;
    out.position.z = (out.position.z + out.position.w) * 0.5;
    out.color = attribute(data, u.attributes[1], u.color, true);
    float4 eye = u.model * p;
    if ((u.flags.w & 1) != 0) {
        float3 normal =
            normalize((u.model * float4(attribute(data, u.attributes[5], u.normal, true).xyz, 0)).xyz);
        float diffuse0 = max(0.0, dot(normal, normalize(u.light0.xyz))) * u.light0.w;
        float diffuse1 = max(0.0, dot(normal, normalize(u.light1.xyz))) * u.light1.w;
        out.color.rgb *= min(float3(1), u.ambient.rgb + diffuse0 + diffuse1);
    }
    float4 uv0 = attribute(data, u.attributes[2], u.coordinates[0], false);
    if ((u.flags.w & 4) != 0)
        uv0 = eye;
    float4 tex0 = u.textureMatrices[0] * float4(uv0.xyz, 1);
    out.uv0 = tex0.xy / tex0.w;
    out.uv1 =
        (u.textureMatrices[1] * float4(attribute(data, u.attributes[3], u.coordinates[1], false).xyz, 1)).xy;
    out.uv2 =
        (u.textureMatrices[2] * float4(attribute(data, u.attributes[4], u.coordinates[2], false).xyz, 1)).xy;
    if ((u.flags.w & 256) != 0)
        out.uv0.y = 1 - out.uv0.y;
    if ((u.flags.w & 512) != 0)
        out.uv1.y = 1 - out.uv1.y;
    if ((u.flags.w & 1024) != 0)
        out.uv2.y = 1 - out.uv2.y;
    out.fogDistance = abs(eye.z);
    return out;
}
vertex DirectOutput direct_vertex(uint id [[vertex_id]], device const uchar *vertices [[buffer(0)]],
                                  constant DirectUniforms &u [[buffer(1)]],
                                  constant uint &stride [[buffer(2)]]) {
    return transformVertex(vertices + id * stride, u, float3(0));
}
bool alphaPass(float value, uint function, float reference) {
    switch (function) {
    case 512:
        return false;
    case 513:
        return value < reference;
    case 514:
        return value == reference;
    case 515:
        return value <= reference;
    case 516:
        return value > reference;
    case 517:
        return value != reference;
    case 518:
        return value >= reference;
    default:
        return true;
    }
}
constant bool directTextured [[function_constant(0)]];
constant bool directOverlay [[function_constant(1)]];
constant bool directLightmap [[function_constant(2)]];
constant bool directAlphaTest [[function_constant(3)]];
constant bool directFog [[function_constant(4)]];
constant bool directOutline [[function_constant(5)]];
fragment float4 direct_fragment(DirectOutput in [[stage_in]], constant DirectUniforms &u [[buffer(1)]],
                                texture2d<float> tex0 [[texture(0)]], texture2d<float> tex1 [[texture(1)]],
                                texture2d<float> tex2 [[texture(2)]], sampler s0 [[sampler(0)]],
                                sampler s1 [[sampler(1)]], sampler s2 [[sampler(2)]]) {
    float4 color = in.color;
    if (directTextured) {
        float4 sample = tex0.sample(s0, in.uv0);
        if (directOutline)
            color.a *= sample.a;
        else
            color *= sample;
    }
    if (directOverlay) {
        float4 overlay = tex1.sample(s1, in.uv1);
        color.rgb = mix(overlay.rgb, color.rgb, overlay.a);
    }
    if (directLightmap)
        color *= tex2.sample(s2, in.uv2);
    if (directAlphaTest && !alphaPass(color.a, u.flags.y, u.fog.w))
        discard_fragment();
    if (directFog) {
        float factor = u.flags.z == 9729
                           ? clamp((u.fog.y - in.fogDistance) / max(0.00001, u.fog.y - u.fog.x), 0.0, 1.0)
                       : u.flags.z == 2048 ? exp(-u.fog.z * in.fogDistance)
                                           : exp(-pow(u.fog.z * in.fogDistance, 2.0));
        color.rgb = mix(u.fogColor.rgb, color.rgb, factor);
    }
    return color;
}
struct PresentOutput {
    float4 position [[position]];
    float2 uv;
};
vertex PresentOutput present_vertex(uint id [[vertex_id]]) {
    float2 p = float2((id << 1) & 2, id & 2);
    return {float4(p * 2 - 1, 0, 1), p};
}
fragment float4 present_fragment(PresentOutput in [[stage_in]], texture2d<float> image [[texture(0)]]) {
    constexpr sampler s(filter::nearest);
    return image.sample(s, in.uv);
}
struct TerrainRecord {
    uint4 geometry;
    int4 origin;
    float4 bounds;
};
struct TerrainFrame {
    DirectUniforms uniforms;
    int4 camera;
    float4 offset;
    float4 planes[6];
    uint4 limits;
};
struct TerrainUnit {
    uint4 geometry;
    int4 origin;
};
struct TerrainArguments {
    uint indexCount;
    atomic_uint instanceCount;
    uint indexStart;
    int baseVertex;
    uint baseInstance;
};
struct PackedTerrainVertex {
    packed_short3 position;
    uchar color[4];
    ushort uv[2];
    uchar light[2];
};
kernel void terrain_cull(device const TerrainRecord *records [[buffer(0)]],
                         constant TerrainFrame &frame [[buffer(1)]],
                         device const uint *visibility [[buffer(2)]], device TerrainUnit *units [[buffer(3)]],
                         device TerrainArguments &arguments [[buffer(4)]],
                         uint index [[thread_position_in_grid]]) {
    if (index >= frame.limits.x)
        return;
    TerrainRecord r = records[index];
    if ((r.geometry.z & 255) != frame.limits.y || r.geometry.y == 0 ||
        (visibility[r.geometry.w >> 5] & (1u << (r.geometry.w & 31))) == 0)
        return;

    uint face=r.geometry.z>>16;
    if(frame.limits.w!=0&&face<6){uint axis=face>>1;float camera=float(frame.camera[axis]-r.origin[axis])-frame.offset[axis];float minimum=r.bounds[axis]-r.bounds.w-1.0/64.0,maximum=r.bounds[axis]+r.bounds.w+1.0/64.0;if((face&1)!=0?camera<minimum:camera>maximum)return;}
    float3 center = float3(r.origin.xyz - frame.camera.xyz) + frame.offset.xyz + r.bounds.xyz;
    for (uint p = 0; p < 6; p++)
        if (dot(frame.planes[p], float4(center, 1)) < -r.bounds.w)
            return;
    uint count = (r.geometry.y + 63) / 64,
         start = atomic_fetch_add_explicit(&arguments.instanceCount, count, memory_order_relaxed);
    for (uint i = 0; i < count; i++) {
        uint offset = i * 64;
        TerrainUnit unit;
        unit.geometry = uint4(r.geometry.x + offset * ((r.geometry.z & 256) != 0 ? 2 : 1),
                              min(64u, r.geometry.y - offset), r.geometry.z, 0);
        unit.origin = r.origin;
        units[start + i] = unit;
    }
}
vertex DirectOutput terrain_vertex(uint id [[vertex_id]], uint instance [[instance_id]],
                                   device const uchar *vertices [[buffer(0)]],
                                   constant TerrainFrame &frame [[buffer(1)]],
                                   device const TerrainUnit *units [[buffer(3)]],
                                   texture2d<float> lightmap [[texture(0)]],
                                   sampler lightSampler [[sampler(0)]]) {
    TerrainUnit unit = units[instance];
    if (id >= unit.geometry.y) {
        DirectOutput out = {};
        out.position = float4(0, 0, 2, 1);
        return out;
    }
    float3 translation = float3(unit.origin.xyz - frame.camera.xyz) + frame.offset.xyz;
    if ((unit.geometry.z & 256) != 0) {
        DirectOutput out =
            transformVertex(vertices + unit.geometry.x * 16 + id * 32, frame.uniforms, translation);
        if ((frame.uniforms.flags.x & 4) != 0)
            out.color *= lightmap.sample(lightSampler, out.uv2, level(0));
        return out;
    }
    device const PackedTerrainVertex &v =
        *reinterpret_cast<device const PackedTerrainVertex *>(vertices + (unit.geometry.x + id) * 16);
    float4 p = float4(float3(v.position) / 1024.0 + translation, 1);
    DirectOutput out;
    out.position = frame.uniforms.mvp * p;
    out.position.y = -out.position.y;
    out.position.z = (out.position.z + out.position.w) * 0.5;
    out.color = float4(v.color[0], v.color[1], v.color[2], v.color[3]) / 255.0;
    float4 uv0 = frame.uniforms.textureMatrices[0] * float4(float2(v.uv[0], v.uv[1]) / 65535.0, 0, 1);
    out.uv0 = uv0.xy / uv0.w;
    out.uv1 = float2(0);
    out.uv2 = (frame.uniforms.textureMatrices[2] * float4(v.light[0], v.light[1], 0, 1)).xy;
    out.fogDistance = abs((frame.uniforms.model * p).z);
    if ((frame.uniforms.flags.x & 4) != 0)
        out.color *= lightmap.sample(lightSampler, out.uv2, level(0));
    return out;
}

fragment float4 direct_logic_fragment(DirectOutput input [[stage_in]],
                                      constant DirectUniforms &uniforms [[buffer(1)]],
                                      float4 destination [[color(0)]]) {
    uint4 source = uint4(round(clamp(input.color, 0.0, 1.0) * 255)),
          value = uint4(round(clamp(destination, 0.0, 1.0) * 255)), result;
    switch (uniforms.flags.w >> 16) {
    case 5376:
        result = uint4(0);
        break;
    case 5377:
        result = source & value;
        break;
    case 5378:
        result = source & ~value;
        break;
    case 5379:
        result = source;
        break;
    case 5380:
        result = ~source & value;
        break;
    case 5381:
        result = value;
        break;
    case 5382:
        result = source ^ value;
        break;
    case 5383:
        result = source | value;
        break;
    case 5384:
        result = ~(source | value);
        break;
    case 5385:
        result = ~(source ^ value);
        break;
    case 5386:
        result = ~value;
        break;
    case 5387:
        result = source | ~value;
        break;
    case 5388:
        result = ~source;
        break;
    case 5389:
        result = ~source | value;
        break;
    case 5390:
        result = ~(source & value);
        break;
    default:
        result = uint4(255);
        break;
    }
    return float4(result & 255u) / 255.0;
}
