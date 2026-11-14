#import <AppKit/AppKit.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#include <jni.h>
#include <math.h>
#import <simd/simd.h>
#include <stdatomic.h>
#include <stdint.h>
#include <string.h>

@interface DirectTexture : NSObject
@property id<MTLTexture> image;
@property id<MTLSamplerState> sampler;
@property NSMutableDictionary<NSNumber *, NSNumber *> *parameters;
@property BOOL renderTarget;
@end
@implementation DirectTexture
- (instancetype)init {
    if ((self = [super init]))
        _parameters = [NSMutableDictionary new];
    return self;
}
@end
@interface DirectBuffer : NSObject
@property id<MTLBuffer> data;
@property NSRange range;
@property int layer;
@property int section;
@property int x;
@property int y;
@property int z;
@property BOOL terrain;
@property BOOL packed;
@property simd_float4 bounds;
@property NSData *faces;
@property NSUInteger vertices;
@end
@implementation DirectBuffer
@end
@interface DirectTarget : NSObject
@property int color;
@property int depth;
@end
@implementation DirectTarget
@end
@interface DirectFrame : NSObject
@property id<MTLCommandBuffer> completion;
@property NSMutableArray<id<MTLBuffer>> *pages;
@property NSUInteger page;
@property NSUInteger offset;
@property id<MTLBuffer> units;
@property NSUInteger unitCapacity;
@end
@implementation DirectFrame
- (instancetype)init {
    if ((self = [super init]))
        _pages = [NSMutableArray new];
    return self;
}
@end
@interface DirectRetirement : NSObject
@property NSRange range;
@property id<MTLCommandBuffer> completion;
@end
@implementation DirectRetirement
@end
@interface DirectEffect : NSObject
@property id<MTLFunction> vertex;
@property id<MTLFunction> fragment;
@property NSData *uniforms;
@property NSData *units;
@end
@implementation DirectEffect
@end
@interface DirectPresentationSlot : NSObject {
  @public
    atomic_bool busy;
}
@property id<MTLTexture> image;
@end
@implementation DirectPresentationSlot
@end
@interface DirectContext : NSObject {
  @public
    atomic_uint_fast64_t handoff;
    atomic_bool presentationScheduled;
    atomic_bool closing;
}
@property id<MTLDevice> device;
@property id<MTLCommandQueue> queue;
@property id<MTLLibrary> library;
@property CAMetalLayer *layer;
@property id<MTLCommandBuffer> command;
@property id<MTLCommandBuffer> lastSubmission;
@property id<MTLRenderCommandEncoder> encoder;
@property id<MTLBlitCommandEncoder> blit;
@property int encoderTarget;
@property NSMutableDictionary<NSNumber *, DirectTexture *> *textures;
@property NSMutableDictionary<NSNumber *, DirectBuffer *> *buffers;
@property NSMutableDictionary<NSNumber *, DirectTarget *> *targets;
@property NSMutableDictionary<NSString *, id<MTLRenderPipelineState>> *pipelines;
@property NSMutableDictionary<NSNumber *, DirectEffect *> *effects;
@property NSMutableDictionary<NSNumber *, id<MTLDepthStencilState>> *depthStates;
@property NSArray<DirectFrame *> *frames;
@property NSUInteger frameIndex;
@property id<MTLRenderPipelineState> presentPipeline;
@property DirectTexture *white;
@property DirectTexture *screen;
@property DirectTexture *screenDepth;
@property id<MTLBuffer> quadIndices;
@property NSUInteger quadCapacity;
@property id<MTLBuffer> arena;
@property NSUInteger arenaCapacity;
@property NSUInteger arenaUsed;
@property NSMutableArray<NSValue *> *freeRanges;
@property NSMutableArray<DirectRetirement *> *retirements;
@property id<MTLBuffer> records;
@property NSUInteger recordCount;
@property NSUInteger unitCount;
@property id<MTLComputePipelineState> cullPipeline;
@property NSUInteger retirementFrame;
@property double gpuMilliseconds;
@property id<MTLCommandQueue> presentationQueue;
@property id<MTLEvent> presentationEvent;
@property dispatch_queue_t presentationWorker;
@property NSArray<DirectPresentationSlot *> *presentationSlots;
@property id<MTLCommandBuffer> lastPresentation;
@property uint64_t presentationValue;
@property NSUInteger nextPresentationSlot;
@property BOOL previousVsync;
@property BOOL collectingTerrain;
@property NSMutableData *terrainUnits;
@property NSData *terrainState;
@property simd_double3 terrainCamera;
@property double fenceMilliseconds;
@property BOOL recordsDirty;
@property id<MTLBuffer> visibility;
@property NSUInteger visibilityOffset;
@end
@implementation DirectContext
@end
static DirectContext *context;
typedef struct {
    float matrices[5][16];
    simd_float4 color, fogColor, fog, light0, light1, ambient, coordinates[3];
    simd_uint4 flags;
    simd_int4 attributes[6];
    simd_float4 normal;
} DirectUniforms;
typedef struct {
    simd_uint4 geometry;
    simd_int4 origin;
    simd_float4 bounds;
} TerrainRecord;
typedef struct {
    DirectUniforms uniforms;
    simd_int4 camera;
    simd_float4 offset;
    simd_float4 planes[6];
    simd_uint4 limits;
} TerrainFrame;
_Static_assert(sizeof(DirectUniforms) == 592, "uniform layout");
typedef struct {
    simd_uint4 geometry;
    simd_int4 origin;
} TerrainUnit;
typedef struct {
    uint32_t offset, count, face;
} TerrainFace;
static void fail(JNIEnv *env, NSString *message) {
    (*env)->ThrowNew(env, (*env)->FindClass(env, "java/lang/IllegalStateException"), message.UTF8String);
}
static DirectTexture *makeTexture(NSUInteger width, NSUInteger height, BOOL depth, BOOL mipmapped) {
    DirectTexture *result = [DirectTexture new];
    MTLTextureDescriptor *descriptor = [MTLTextureDescriptor
        texture2DDescriptorWithPixelFormat:depth ? MTLPixelFormatDepth32Float : MTLPixelFormatRGBA8Unorm
                                     width:MAX(1, width)
                                    height:MAX(1, height)
                                 mipmapped:!depth && mipmapped];
    descriptor.storageMode = MTLStorageModePrivate;
    descriptor.usage = MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget;
    result.image = [context.device newTextureWithDescriptor:descriptor];
    return result;
}
static void endEncoder(void) {
    if (context.blit) {
        [context.blit endEncoding];
        context.blit = nil;
    }
    if (context.encoder) {
        [context.encoder endEncoding];
        context.encoder = nil;
    }
}
static void begin(void) {
    if (context.command)
        return;
    DirectFrame *frame = context.frames[context.frameIndex % 3];
    if (frame.completion) {
        double waitStart = CACurrentMediaTime();
        [frame.completion waitUntilCompleted];
        context.fenceMilliseconds = (CACurrentMediaTime() - waitStart) * 1000;
        context.gpuMilliseconds = (frame.completion.GPUEndTime - frame.completion.GPUStartTime) * 1000;
        if (frame.completion.error)
            @throw [NSException exceptionWithName:@"Metal command failure"
                                           reason:frame.completion.error.description
                                         userInfo:nil];
        frame.completion = nil;
    }
    frame.page = 0;
    frame.offset = 0;
    context.command = [context.queue commandBuffer];
    context.command.label = @"Minecraft direct Metal frame";
}
static id<MTLBuffer> stage(const void *bytes, NSUInteger size, NSUInteger *offset) {
    begin();
    DirectFrame *frame = context.frames[context.frameIndex % 3];
    NSUInteger aligned = (size + 255) & ~255ULL;
    for (;;) {
        if (frame.page >= frame.pages.count) {
            NSUInteger length = MAX(4 * 1024 * 1024ULL, aligned);
            [frame.pages addObject:[context.device newBufferWithLength:length
                                                               options:MTLResourceStorageModeShared]];
        }
        id<MTLBuffer> page = frame.pages[frame.page];
        if (frame.offset + aligned <= page.length) {
            *offset = frame.offset;
            if (bytes)
                memcpy((uint8_t *)page.contents + *offset, bytes, size);
            frame.offset += aligned;
            return page;
        }
        frame.page++;
        frame.offset = 0;
    }
}
static id<MTLBlitCommandEncoder> textureBlitter(void) {
    begin();
    if (context.encoder) {
        [context.encoder endEncoding];
        context.encoder = nil;
    }
    if (!context.blit)
        context.blit = [context.command blitCommandEncoder];
    return context.blit;
}
static DirectTexture *colorForTarget(int target) {
    return target == 0 ? context.screen : context.textures[@(context.targets[@(target)].color)];
}
static DirectTexture *depthForTarget(int target) {
    return target == 0 ? context.screenDepth : context.textures[@(context.targets[@(target)].depth)];
}
static MTLRenderPassDescriptor *pass(int target, int clearMask, MTLClearColor color, double depth) {
    DirectTexture *image = colorForTarget(target), *depthImage = depthForTarget(target);
    if (!image.image)
        return nil;
    MTLRenderPassDescriptor *p = [MTLRenderPassDescriptor renderPassDescriptor];
    p.colorAttachments[0].texture = image.image;
    p.colorAttachments[0].loadAction = clearMask & 16384 ? MTLLoadActionClear : MTLLoadActionLoad;
    p.colorAttachments[0].storeAction = MTLStoreActionStore;
    p.colorAttachments[0].clearColor = color;
    if (depthImage.image) {
        p.depthAttachment.texture = depthImage.image;
        p.depthAttachment.loadAction = clearMask & 256 ? MTLLoadActionClear : MTLLoadActionLoad;
        p.depthAttachment.storeAction = MTLStoreActionStore;
        p.depthAttachment.clearDepth = depth;
    }
    return p;
}
static id<MTLRenderCommandEncoder> encoder(int target) {
    begin();
    if (context.encoder && context.encoderTarget == target)
        return context.encoder;
    endEncoder();
    MTLRenderPassDescriptor *p = pass(target, 0, MTLClearColorMake(0, 0, 0, 0), 1);
    if (!p)
        return nil;
    context.encoder = [context.command renderCommandEncoderWithDescriptor:p];
    context.encoderTarget = target;
    return context.encoder;
}
static MTLBlendFactor blendFactor(int value) {
    switch (value) {
    case 0:
        return MTLBlendFactorZero;
    case 1:
        return MTLBlendFactorOne;
    case 768:
        return MTLBlendFactorSourceColor;
    case 769:
        return MTLBlendFactorOneMinusSourceColor;
    case 770:
        return MTLBlendFactorSourceAlpha;
    case 771:
        return MTLBlendFactorOneMinusSourceAlpha;
    case 772:
        return MTLBlendFactorDestinationAlpha;
    case 773:
        return MTLBlendFactorOneMinusDestinationAlpha;
    case 774:
        return MTLBlendFactorDestinationColor;
    case 775:
        return MTLBlendFactorOneMinusDestinationColor;
    case 776:
        return MTLBlendFactorSourceAlphaSaturated;
    case 32769:
        return MTLBlendFactorBlendColor;
    case 32770:
        return MTLBlendFactorOneMinusBlendColor;
    case 32771:
        return MTLBlendFactorBlendAlpha;
    case 32772:
        return MTLBlendFactorOneMinusBlendAlpha;
    default:
        return MTLBlendFactorOne;
    }
}
static MTLBlendOperation blendOperation(int value) {
    switch (value) {
    case 32778:
        return MTLBlendOperationSubtract;
    case 32779:
        return MTLBlendOperationReverseSubtract;
    case 32775:
        return MTLBlendOperationMin;
    case 32776:
        return MTLBlendOperationMax;
    default:
        return MTLBlendOperationAdd;
    }
}
static MTLColorWriteMask writeMask(int value) {
    return (value & 1 ? MTLColorWriteMaskRed : 0) | (value & 2 ? MTLColorWriteMaskGreen : 0) |
           (value & 4 ? MTLColorWriteMaskBlue : 0) | (value & 8 ? MTLColorWriteMaskAlpha : 0);
}
static id<MTLRenderPipelineState> pipeline(JNIEnv *env, const int *p, BOOL terrain, BOOL depth) {
    const DirectUniforms *u = (const DirectUniforms *)((const uint8_t *)p - 640);
    uint32_t features = (u->flags.x & (terrain ? 3u : 7u)) | (u->flags.y ? 8u : 0u) |
                        (u->flags.z ? 16u : 0u) | ((u->flags.w & 2) ? 32u : 0u);
    NSString *key =
        [NSString stringWithFormat:@"%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%u", terrain, depth, p[1], p[2],
                                   p[3], p[4], p[5], p[6], p[11], p[26], p[24], p[27], features];
    id<MTLRenderPipelineState> result = context.pipelines[key];
    if (result)
        return result;
    NSError *error = nil;

    MTLRenderPipelineDescriptor *d = [MTLRenderPipelineDescriptor new];
    DirectEffect *effect = context.effects[@(p[26])];
    d.vertexFunction =
        effect ? effect.vertex
               : [context.library newFunctionWithName:terrain ? @"terrain_vertex" : @"direct_vertex"];
    if (effect)
        d.fragmentFunction = effect.fragment;
    else if (p[27])
        d.fragmentFunction = [context.library newFunctionWithName:@"direct_logic_fragment"];
    else {
        MTLFunctionConstantValues *constants = [MTLFunctionConstantValues new];
        for (int i = 0; i < 6; i++) {
            bool value = (features & (1u << i)) != 0;
            [constants setConstantValue:&value type:MTLDataTypeBool atIndex:i];
        }
        d.fragmentFunction = [context.library newFunctionWithName:@"direct_fragment"
                                                   constantValues:constants
                                                            error:&error];
        if (!d.fragmentFunction) {
            fail(env, error.description);
            return nil;
        }
    }
    if (effect) {
        MTLVertexDescriptor *vd = [MTLVertexDescriptor vertexDescriptor];
        vd.attributes[0].format = MTLVertexFormatFloat3;
        vd.attributes[0].offset = 0;
        vd.attributes[0].bufferIndex = 0;
        vd.layouts[0].stride = p[24];
        d.vertexDescriptor = vd;
    }
    d.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA8Unorm;
    d.depthAttachmentPixelFormat = depth ? MTLPixelFormatDepth32Float : MTLPixelFormatInvalid;
    MTLRenderPipelineColorAttachmentDescriptor *a = d.colorAttachments[0];
    a.blendingEnabled = p[27] ? NO : p[1];
    a.sourceRGBBlendFactor = blendFactor(p[2]);
    a.destinationRGBBlendFactor = blendFactor(p[3]);
    a.sourceAlphaBlendFactor = blendFactor(p[4]);
    a.destinationAlphaBlendFactor = blendFactor(p[5]);
    a.rgbBlendOperation = a.alphaBlendOperation = blendOperation(p[6]);
    a.writeMask = writeMask(p[11]);
    result = [context.device newRenderPipelineStateWithDescriptor:d error:&error];
    if (!result) {
        fail(env, error.description);
        return nil;
    }
    context.pipelines[key] = result;
    return result;
}
static id<MTLSamplerState> sampler(DirectTexture *texture) {
    if (texture.sampler)
        return texture.sampler;
    MTLSamplerDescriptor *d = [MTLSamplerDescriptor new];
    int min = texture.parameters[@10241] ? texture.parameters[@10241].intValue : 9728;
    int mag = texture.parameters[@10240] ? texture.parameters[@10240].intValue : 9728;
    d.minFilter = min == 9729 || min == 9985 || min == 9987 ? MTLSamplerMinMagFilterLinear
                                                            : MTLSamplerMinMagFilterNearest;
    d.magFilter = mag == 9729 ? MTLSamplerMinMagFilterLinear : MTLSamplerMinMagFilterNearest;
    d.mipFilter = min == 9984 || min == 9985   ? MTLSamplerMipFilterNearest
                  : min == 9986 || min == 9987 ? MTLSamplerMipFilterLinear
                                               : MTLSamplerMipFilterNotMipmapped;
    d.lodMinClamp = 0;
    d.lodMaxClamp = texture.parameters[@33085] ? texture.parameters[@33085].floatValue : 0;
    d.sAddressMode =
        texture.parameters[@10242].intValue == 10496 || texture.parameters[@10242].intValue == 33071
            ? MTLSamplerAddressModeClampToEdge
            : MTLSamplerAddressModeRepeat;
    d.tAddressMode =
        texture.parameters[@10243].intValue == 10496 || texture.parameters[@10243].intValue == 33071
            ? MTLSamplerAddressModeClampToEdge
            : MTLSamplerAddressModeRepeat;
    texture.sampler = [context.device newSamplerStateWithDescriptor:d];
    return texture.sampler;
}
static DirectUniforms uniforms(const uint8_t *state) {
    DirectUniforms u;
    memcpy(&u, state, sizeof u);
    u.flags.w |= ((const int *)(state + 640))[27] << 16;
    const int *textures = (const int *)(state + 768);
    (void)textures;
    return u;
}
static void apply(id<MTLRenderCommandEncoder> e, const uint8_t *state, BOOL depth) {
    const int *p = (const int *)(state + 640);
    int compare = p[7] ? p[8] - 512 : 7;
    compare = MAX(0, MIN(7, compare));
    NSNumber *key = @(compare * 2 + (p[9] && p[7] ? 1 : 0));
    id<MTLDepthStencilState> ds = context.depthStates[key];
    if (!ds) {
        MTLDepthStencilDescriptor *d = [MTLDepthStencilDescriptor new];
        d.depthCompareFunction = compare;
        d.depthWriteEnabled = p[9] && p[7];
        ds = [context.device newDepthStencilStateWithDescriptor:d];
        context.depthStates[key] = ds;
    }
    if (depth)
        [e setDepthStencilState:ds];
    [e setCullMode:p[10] ? MTLCullModeBack : MTLCullModeNone];
    [e setFrontFacingWinding:MTLWindingClockwise];
    float factor, units;
    memcpy(&factor, &p[13], 4);
    memcpy(&units, &p[14], 4);
    [e setDepthBias:p[12] ? units : 0 slopeScale:p[12] ? factor : 0 clamp:0];
    DirectTexture *target = colorForTarget(p[0]);
    double y = p[21];
    (void)target;
    [e setViewport:(MTLViewport){p[20], y, p[22], p[23], 0, 1}];
    const int *ids = (const int *)(state + 768);
    for (int unit = 0; unit < 3; unit++) {
        DirectTexture *t = context.textures[@(ids[unit])] ?: context.white;
        if (!t.image)
            t = context.white;
        [e setFragmentTexture:t.image atIndex:unit];
        [e setFragmentSamplerState:sampler(t) atIndex:unit];
    }
}
static void retire(NSRange range) {
    if (!range.length)
        return;
    DirectRetirement *r = [DirectRetirement new];
    r.range = range;
    r.completion = context.command ?: context.lastSubmission;
    if (!r.completion || r.completion.status >= MTLCommandBufferStatusCompleted)
        [context.freeRanges addObject:[NSValue valueWithRange:range]];
    else
        [context.retirements addObject:r];
}
static NSRange allocate(NSUInteger vertices) {
    if (context.retirementFrame != context.frameIndex) {
        context.retirementFrame = context.frameIndex;
        for (NSInteger i = context.retirements.count - 1; i >= 0; i--) {
            DirectRetirement *r = context.retirements[i];
            if (r.completion.status >= MTLCommandBufferStatusCompleted) {
                [context.freeRanges addObject:[NSValue valueWithRange:r.range]];
                [context.retirements removeObjectAtIndex:i];
            }
        }
        [context.freeRanges sortUsingComparator:^NSComparisonResult(NSValue *a, NSValue *b) {
          return a.rangeValue.location < b.rangeValue.location   ? NSOrderedAscending
                 : a.rangeValue.location > b.rangeValue.location ? NSOrderedDescending
                                                                 : NSOrderedSame;
        }];
        for (NSUInteger i = 1; i < context.freeRanges.count;) {
            NSRange previous = context.freeRanges[i - 1].rangeValue,
                    current = context.freeRanges[i].rangeValue;
            if (NSMaxRange(previous) == current.location) {
                context.freeRanges[i - 1] =
                    [NSValue valueWithRange:NSMakeRange(previous.location, previous.length + current.length)];
                [context.freeRanges removeObjectAtIndex:i];
            } else
                i++;
        }
    }
    for (NSUInteger i = 0; i < context.freeRanges.count; i++) {
        NSRange range = context.freeRanges[i].rangeValue;
        if (range.length >= vertices) {
            NSRange result = NSMakeRange(range.location, vertices);
            range.location += vertices;
            range.length -= vertices;
            if (range.length)
                context.freeRanges[i] = [NSValue valueWithRange:range];
            else
                [context.freeRanges removeObjectAtIndex:i];
            return result;
        }
    }
    if (context.arenaUsed + vertices > context.arenaCapacity) {
        NSUInteger capacity = MAX(1048576ULL, MAX(context.arenaCapacity * 2, context.arenaUsed + vertices));
        if (capacity * 16 > context.device.maxBufferLength)
            return NSMakeRange(NSNotFound, 0);
        id<MTLBuffer> arena = [context.device newBufferWithLength:capacity * 16
                                                          options:MTLResourceStorageModeShared];
        if (!arena)
            return NSMakeRange(NSNotFound, 0);
        if (context.arena)
            memcpy(arena.contents, context.arena.contents, context.arenaUsed * 16);
        context.arena = arena;
        context.arenaCapacity = capacity;
    }
    NSRange result = NSMakeRange(context.arenaUsed, vertices);
    context.arenaUsed += vertices;
    return result;
}
static void rebuildRecords(void) {
    if (!context.recordsDirty)
        return;
    NSMutableData *data = [NSMutableData new];
    NSUInteger units = 0;
    for (NSNumber *identifier in context.buffers) {
        DirectBuffer *b = context.buffers[identifier];
        if (!b.terrain || b.layer > 2 || !b.vertices)
            continue;
        const TerrainFace *faces = b.faces.bytes;
        NSUInteger count = b.faces.length / sizeof(TerrainFace);
        for (NSUInteger i = 0; i < count; i++) {
            TerrainFace face = faces[i];
            if (!face.count)
                continue;
            TerrainRecord record = {{(uint32_t)(b.range.location + face.offset * (b.packed ? 1 : 2)),
                                     face.count, (uint32_t)b.layer | (b.packed ? 0 : 256) | (face.face << 16),
                                     (uint32_t)b.section},
                                    {b.x, b.y, b.z, 0},
                                    b.bounds};
            [data appendBytes:&record length:sizeof record];
            units += (face.count + 63) / 64;
        }
    }
    context.unitCount = units;
    context.recordCount = data.length / sizeof(TerrainRecord);
    context.records = context.recordCount ? [context.device newBufferWithBytes:data.bytes
                                                                        length:data.length
                                                                       options:MTLResourceStorageModeShared]
                                          : nil;
    context.recordsDirty = NO;
}
static uint32_t quadFace(const uint8_t *data) {
    simd_float3 p[4];
    for (int i = 0; i < 4; i++) {
        float values[3];
        memcpy(values, data + i * 32, 12);
        p[i] = (simd_float3){values[0], values[1], values[2]};
    }
    simd_float3 normal = simd_cross(p[1] - p[0], p[2] - p[0]), second = simd_cross(p[2] - p[0], p[3] - p[0]);
    if (simd_dot(normal, second) < 0)
        return 6;
    simd_float3 magnitude = simd_abs(normal);
    int axis = magnitude.x >= magnitude.y && magnitude.x >= magnitude.z ? 0
               : magnitude.y >= magnitude.z                             ? 1
                                                                        : 2;
    if (magnitude[axis] < 0.000001f)
        return 6;
    for (int i = 0; i < 3; i++)
        if (i != axis && magnitude[i] > magnitude[axis] * 0.00001f)
            return 6;
    if (fabsf(p[3][axis] - p[0][axis]) > 0.00001f)
        return 6;
    return (uint32_t)axis * 2 + (normal[axis] > 0 ? 1 : 0);
}
static NSData *orderTerrainFaces(DirectBuffer *buffer, const uint8_t *input, NSUInteger size) {
    if (buffer.layer >= 3) {
        buffer.faces = nil;
        return nil;
    }
    uint32_t counts[7] = {0}, offsets[7], next[7];
    for (NSUInteger quad = 0; quad < size / 128; quad++)
        counts[quadFace(input + quad * 128)] += 4;
    uint32_t offset = 0;
    TerrainFace spans[7];
    for (int i = 0; i < 7; i++) {
        offsets[i] = next[i] = offset;
        spans[i] = (TerrainFace){offset, counts[i], (uint32_t)i};
        offset += counts[i];
    }
    NSMutableData *ordered = [NSMutableData dataWithLength:size];
    uint8_t *output = ordered.mutableBytes;
    for (NSUInteger quad = 0; quad < size / 128; quad++) {
        uint32_t face = quadFace(input + quad * 128);
        memcpy(output + (NSUInteger)next[face] * 32, input + quad * 128, 128);
        next[face] += 4;
    }
    buffer.faces = [NSData dataWithBytes:spans length:sizeof spans];
    (void)offsets;
    return ordered;
}
typedef struct __attribute__((packed)) {
    int16_t position[3];
    uint8_t color[4];
    uint16_t uv[2];
    uint8_t light[2];
} PackedTerrainVertex;
_Static_assert(sizeof(PackedTerrainVertex) == 16, "packed terrain layout");
static void quadIndices(NSUInteger quads) {
    if (quads <= context.quadCapacity)
        return;
    NSUInteger capacity = MAX(quads, MAX(16384ULL, context.quadCapacity * 2));
    context.quadIndices = [context.device newBufferWithLength:capacity * 6 * 4
                                                      options:MTLResourceStorageModeShared];
    uint32_t *indices = context.quadIndices.contents;
    for (NSUInteger i = 0; i < capacity; i++) {
        uint32_t v = (uint32_t)i * 4;
        uint32_t q[] = {v, v + 1, v + 2, v + 2, v + 3, v};
        memcpy(indices + i * 6, q, sizeof q);
    }
    context.quadCapacity = capacity;
}
JNIEXPORT jstring JNICALL Java_mcopt_legacy_DirectNative_initialize(JNIEnv *env, jclass type, jlong window,
                                                                    jstring source) {
    (void)type;
    @autoreleasepool {
        context = [DirectContext new];
        context.device = MTLCreateSystemDefaultDevice();
        if (!context.device) {
            fail(env, @"no Metal device");
            return NULL;
        }
        context.queue = [context.device newCommandQueue];
        context.textures = [NSMutableDictionary new];
        context.buffers = [NSMutableDictionary new];
        context.targets = [NSMutableDictionary new];
        context.pipelines = [NSMutableDictionary new];
        context.effects = [NSMutableDictionary new];
        context.depthStates = [NSMutableDictionary new];
        context.freeRanges = [NSMutableArray new];
        context.retirements = [NSMutableArray new];
        context.frames = @[ [DirectFrame new], [DirectFrame new], [DirectFrame new] ];
        context.retirementFrame = NSUIntegerMax;
        context.presentationQueue = [context.device newCommandQueue];
        context.presentationEvent = [context.device newEvent];
        context.presentationSlots =
            @[ [DirectPresentationSlot new], [DirectPresentationSlot new], [DirectPresentationSlot new] ];
        context.presentationWorker = dispatch_queue_create(
            "mcopt.legacy.presentation",
            dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INTERACTIVE, 0));
        const char *text = (*env)->GetStringUTFChars(env, source, NULL);
        NSString *shader = [NSString stringWithUTF8String:text];
        (*env)->ReleaseStringUTFChars(env, source, text);
        NSError *error = nil;
        MTLCompileOptions *options = [MTLCompileOptions new];
        options.languageVersion = MTLLanguageVersion3_0;
        context.library = [context.device newLibraryWithSource:shader options:options error:&error];
        if (!context.library) {
            fail(env, error.description);
            return NULL;
        }
        context.cullPipeline = [context.device
            newComputePipelineStateWithFunction:[context.library newFunctionWithName:@"terrain_cull"]
                                          error:&error];
        if (!context.cullPipeline) {
            fail(env, error.description);
            return NULL;
        }
        NSWindow *nativeWindow = (__bridge NSWindow *)(void *)(intptr_t)window;
        NSView *view = nativeWindow.contentView;
        context.layer = [CAMetalLayer layer];
        context.layer.device = context.device;
        context.layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
        context.layer.framebufferOnly = YES;
        context.layer.opaque = YES;
        context.layer.maximumDrawableCount = 3;
        context.layer.contentsScale = nativeWindow.backingScaleFactor;
        context.layer.drawableSize = [view convertRectToBacking:view.bounds].size;
        view.wantsLayer = YES;
        view.layer = context.layer;
        MTLRenderPipelineDescriptor *d = [MTLRenderPipelineDescriptor new];
        d.vertexFunction = [context.library newFunctionWithName:@"present_vertex"];
        d.fragmentFunction = [context.library newFunctionWithName:@"present_fragment"];
        d.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
        context.presentPipeline = [context.device newRenderPipelineStateWithDescriptor:d error:&error];
        if (!context.presentPipeline) {
            fail(env, error.description);
            return NULL;
        }
        NSUInteger width = MAX(1, (NSUInteger)context.layer.drawableSize.width),
                   height = MAX(1, (NSUInteger)context.layer.drawableSize.height);
        context.screen = makeTexture(width, height, NO, NO);
        context.screenDepth = makeTexture(width, height, YES, NO);
        context.white = [DirectTexture new];
        MTLTextureDescriptor *white =
            [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                               width:1
                                                              height:1
                                                           mipmapped:NO];
        white.storageMode = MTLStorageModeShared;
        context.white.image = [context.device newTextureWithDescriptor:white];
        uint32_t pixel = UINT32_MAX;
        [context.white.image replaceRegion:MTLRegionMake2D(0, 0, 1, 1)
                               mipmapLevel:0
                                 withBytes:&pixel
                               bytesPerRow:4];
        return (*env)->NewStringUTF(env, context.device.name.UTF8String);
    }
}
static void drawPresentation(DirectContext *ctx, id<MTLCommandBuffer> command, id<CAMetalDrawable> drawable,
                             id<MTLTexture> source) {
    MTLRenderPassDescriptor *p = [MTLRenderPassDescriptor renderPassDescriptor];
    p.colorAttachments[0].texture = drawable.texture;
    p.colorAttachments[0].loadAction = MTLLoadActionDontCare;
    p.colorAttachments[0].storeAction = MTLStoreActionStore;
    id<MTLRenderCommandEncoder> e = [command renderCommandEncoderWithDescriptor:p];
    [e setRenderPipelineState:ctx.presentPipeline];
    [e setFragmentTexture:source atIndex:0];
    [e drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    [e endEncoding];
    [command presentDrawable:drawable];
}
static void presentationWork(DirectContext *ctx) {
    for (;;) {
        atomic_store(&ctx->presentationScheduled, false);
        uint64_t handoff = atomic_exchange(&ctx->handoff, 0);
        if (!handoff)
            return;
        DirectPresentationSlot *slot = ctx.presentationSlots[handoff & 3];
        @autoreleasepool {
            if (atomic_load(&ctx->closing)) {
                atomic_store(&slot->busy, false);
                continue;
            }
            id<CAMetalDrawable> drawable = [ctx.layer nextDrawable];
            if (!drawable || atomic_load(&ctx->closing)) {
                atomic_store(&slot->busy, false);
                continue;
            }
            id<MTLCommandBuffer> command = [ctx.presentationQueue commandBuffer];
            [command encodeWaitForEvent:ctx.presentationEvent value:handoff >> 2];
            drawPresentation(ctx, command, drawable, slot.image);
            [command addCompletedHandler:^(id<MTLCommandBuffer> finished) {
              (void)finished;
              atomic_store(&slot->busy, false);
            }];
            ctx.lastPresentation = command;
            [command commit];
        }
    }
}
static uint64_t stagePresentation(DirectContext *ctx) {
    for (NSUInteger i = 0; i < 3; i++) {
        NSUInteger index = (ctx.nextPresentationSlot + i) % 3;
        DirectPresentationSlot *slot = ctx.presentationSlots[index];
        if (atomic_exchange(&slot->busy, true))
            continue;
        ctx.nextPresentationSlot = (index + 1) % 3;
        id<MTLTexture> source = ctx.screen.image;
        if (!slot.image || slot.image.width != source.width || slot.image.height != source.height) {
            MTLTextureDescriptor *d =
                [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:source.pixelFormat
                                                                   width:source.width
                                                                  height:source.height
                                                               mipmapped:NO];
            d.storageMode = MTLStorageModePrivate;
            d.usage = MTLTextureUsageShaderRead;
            slot.image = [ctx.device newTextureWithDescriptor:d];
        }
        id<MTLBlitCommandEncoder> blit = [ctx.command blitCommandEncoder];
        [blit copyFromTexture:source
                  sourceSlice:0
                  sourceLevel:0
                 sourceOrigin:MTLOriginMake(0, 0, 0)
                   sourceSize:MTLSizeMake(source.width, source.height, 1)
                    toTexture:slot.image
             destinationSlice:0
             destinationLevel:0
            destinationOrigin:MTLOriginMake(0, 0, 0)];
        [blit endEncoding];
        uint64_t value = ctx.presentationValue + 1;
        ctx.presentationValue = value;
        [ctx.command encodeSignalEvent:ctx.presentationEvent value:value];
        return value << 2 | index;
    }
    return 0;
}
static void publishPresentation(DirectContext *ctx, uint64_t value) {
    if (!value)
        return;
    uint64_t old = atomic_exchange(&ctx->handoff, value);
    if (old)
        atomic_store(&ctx.presentationSlots[old & 3]->busy, false);
    if (!atomic_exchange(&ctx->presentationScheduled, true))
        dispatch_async(ctx.presentationWorker, ^{
          presentationWork(ctx);
        });
}
JNIEXPORT void JNICALL Java_mcopt_legacy_DirectNative_present(JNIEnv *env, jclass type, jint width,
                                                              jint height, jboolean vsync) {
    (void)type;
    @autoreleasepool {
        DirectContext *ctx = context;
        if (!ctx)
            return;
        begin();
        endEncoder();
        ctx.layer.displaySyncEnabled = vsync;
        if (vsync && !ctx.previousVsync) {
            uint64_t old = atomic_exchange(&ctx->handoff, 0);
            if (old)
                atomic_store(&ctx.presentationSlots[old & 3]->busy, false);
            dispatch_sync(ctx.presentationWorker, ^{
                          });
            [ctx.lastPresentation waitUntilCompleted];
        }
        ctx.previousVsync = vsync;
        uint64_t handoff = 0;
        if (vsync) {
            id<CAMetalDrawable> drawable = [ctx.layer nextDrawable];
            if (drawable)
                drawPresentation(ctx, ctx.command, drawable, ctx.screen.image);
        } else
            handoff = stagePresentation(ctx);
        DirectFrame *frame = ctx.frames[ctx.frameIndex % 3];
        frame.completion = ctx.command;
        ctx.lastSubmission = ctx.command;
        [ctx.command commit];
        ctx.command = nil;
        ctx.frameIndex++;
        publishPresentation(ctx, handoff);
        if (width > 0 && height > 0 &&
            (ctx.screen.image.width != (NSUInteger)width || ctx.screen.image.height != (NSUInteger)height)) {
            ctx.layer.drawableSize = CGSizeMake(width, height);
            ctx.screen = makeTexture(width, height, NO, NO);
            ctx.screenDepth = makeTexture(width, height, YES, NO);
        }
        if (ctx.lastSubmission.status == MTLCommandBufferStatusError)
            fail(env, ctx.lastSubmission.error.description);
    }
}
JNIEXPORT void JNICALL Java_mcopt_legacy_DirectNative_close(JNIEnv *env, jclass type) {
    (void)env;
    (void)type;
    @autoreleasepool {
        DirectContext *ctx = context;
        if (!ctx)
            return;
        atomic_store(&ctx->closing, true);
        uint64_t old = atomic_exchange(&ctx->handoff, 0);
        if (old)
            atomic_store(&ctx.presentationSlots[old & 3]->busy, false);
        endEncoder();
        if (ctx.command) {
            [ctx.command commit];
            [ctx.command waitUntilCompleted];
        } else
            [ctx.lastSubmission waitUntilCompleted];
        dispatch_sync(ctx.presentationWorker, ^{
                      });
        [ctx.lastPresentation waitUntilCompleted];
        ctx.layer = nil;
        context = nil;
    }
}
JNIEXPORT void JNICALL Java_mcopt_legacy_DirectNative_texture(JNIEnv *env, jclass type, jint identifier,
                                                              jint width, jint height, jboolean depth) {
    (void)type;
    @autoreleasepool {
        if (width < 1 || height < 1) {
            fail(env, @"invalid texture size");
            return;
        }
        DirectTexture *old = context.textures[@(identifier)], *t = makeTexture(width, height, depth, YES);
        if (!t.image) {
            fail(env, @"Metal texture allocation failed");
            return;
        }
        if (old)
            t.parameters = old.parameters;
        context.textures[@(identifier)] = t;
    }
}
JNIEXPORT void JNICALL Java_mcopt_legacy_DirectNative_textureParameter(JNIEnv *env, jclass type,
                                                                       jint identifier, jint key,
                                                                       jint value) {
    (void)env;
    (void)type;
    @autoreleasepool {
        DirectTexture *t = context.textures[@(identifier)];
        if (!t) {
            t = [DirectTexture new];
            context.textures[@(identifier)] = t;
        }
        if (![t.parameters[@(key)] isEqual:@(value)]) {
            t.parameters[@(key)] = @(value);
            t.sampler = nil;
        }
    }
}
JNIEXPORT void JNICALL Java_mcopt_legacy_DirectNative_uploadTexture(JNIEnv *env, jclass type, jint identifier,
                                                                    jint level, jint x, jint y, jint width,
                                                                    jint height, jint rowBytes, jint format,
                                                                    jint elementType, jlong address) {
    (void)type;
    @autoreleasepool {
        DirectTexture *t = context.textures[@(identifier)];
        if (!t.image || !address || width <= 0 || height <= 0)
            return;
        if (level < 0 || (NSUInteger)level >= t.image.mipmapLevelCount || x < 0 || y < 0 ||
            x + width > MAX(1, (int)t.image.width >> level) ||
            y + height > MAX(1, (int)t.image.height >> level)) {
            fail(env, @"texture upload outside allocation");
            return;
        }
        NSUInteger stride = ((NSUInteger)width * 4 + 255) & ~255ULL, offset;
        id<MTLBuffer> upload = stage(NULL, stride * height, &offset);
        uint8_t *destination = (uint8_t *)upload.contents + offset;
        const uint8_t *source = (const uint8_t *)(intptr_t)address;
        int components = format == 6408 || format == 32993   ? 4
                         : format == 6407                    ? 3
                         : format == 33319 || format == 6410 ? 2
                                                             : 1;
        for (int row = 0; row < height; row++)
            for (int col = 0; col < width; col++) {
                const uint8_t *p = source + (size_t)row * rowBytes + (size_t)col * components;
                uint8_t *q = destination + (size_t)row * stride + (size_t)col * 4;
                if (format == 6408) {
                    memcpy(q, p, 4);
                } else if (format == 32993) {
                    q[0] = p[2];
                    q[1] = p[1];
                    q[2] = p[0];
                    q[3] = p[3];
                } else if (format == 6407) {
                    q[0] = p[0];
                    q[1] = p[1];
                    q[2] = p[2];
                    q[3] = 255;
                } else if (format == 6406) {
                    q[0] = q[1] = q[2] = 255;
                    q[3] = p[0];
                } else {
                    q[0] = q[1] = q[2] = p[0];
                    q[3] = components == 2 ? p[1] : 255;
                }
            }
        (void)elementType;
        id<MTLBlitCommandEncoder> e = textureBlitter();
        [e copyFromBuffer:upload
                   sourceOffset:offset
              sourceBytesPerRow:stride
            sourceBytesPerImage:stride * height
                     sourceSize:MTLSizeMake(width, height, 1)
                      toTexture:t.image
               destinationSlice:0
               destinationLevel:level
              destinationOrigin:MTLOriginMake(x, y, 0)];
    }
}
JNIEXPORT void JNICALL Java_mcopt_legacy_DirectNative_deleteTexture(JNIEnv *env, jclass type,
                                                                    jint identifier) {
    (void)env;
    (void)type;
    @autoreleasepool {
        endEncoder();
        [context.textures removeObjectForKey:@(identifier)];
    }
}
JNIEXPORT void JNICALL Java_mcopt_legacy_DirectNative_attach(JNIEnv *env, jclass type, jint target,
                                                             jint attachment, jint texture) {
    (void)env;
    (void)type;
    @autoreleasepool {
        endEncoder();
        DirectTarget *t = context.targets[@(target)];
        if (!t) {
            t = [DirectTarget new];
            context.targets[@(target)] = t;
        }
        if (attachment == 36064)
            t.color = texture;
        else if (attachment == 36096)
            t.depth = texture;
        context.textures[@(texture)].renderTarget = YES;
    }
}
JNIEXPORT void JNICALL Java_mcopt_legacy_DirectNative_deleteTarget(JNIEnv *env, jclass type,
                                                                   jint identifier) {
    (void)env;
    (void)type;
    @autoreleasepool {
        endEncoder();
        [context.targets removeObjectForKey:@(identifier)];
    }
}
JNIEXPORT void JNICALL Java_mcopt_legacy_DirectNative_clear(JNIEnv *env, jclass type, jint target, jint mask,
                                                            jfloat red, jfloat green, jfloat blue,
                                                            jfloat alpha, jdouble depth) {
    (void)env;
    (void)type;
    @autoreleasepool {
        begin();
        endEncoder();
        MTLRenderPassDescriptor *p = pass(target, mask, MTLClearColorMake(red, green, blue, alpha), depth);
        if (p) {
            id<MTLRenderCommandEncoder> e = [context.command renderCommandEncoderWithDescriptor:p];
            [e endEncoding];
        }
    }
}
JNIEXPORT void JNICALL Java_mcopt_legacy_DirectNative_uploadBuffer(JNIEnv *env, jclass type, jint identifier,
                                                                   jobject bytes) {
    (void)type;
    @autoreleasepool {
        const uint8_t *data = (*env)->GetDirectBufferAddress(env, bytes);
        jlong size = (*env)->GetDirectBufferCapacity(env, bytes);
        DirectBuffer *b = context.buffers[@(identifier)];
        if (!b) {
            b = [DirectBuffer new];
            b.layer = -1;
            context.buffers[@(identifier)] = b;
        }
        if (b.terrain) {
            NSUInteger vertexCount = (NSUInteger)size / 32;
            if (!b.vertices && !vertexCount)
                return;
            if (b.layer < 3)
                context.recordsDirty = YES;
            NSData *ordered = orderTerrainFaces(b, data, (NSUInteger)size);
            if (ordered)
                data = ordered.bytes;
            retire(b.range);
            b.range = NSMakeRange(0, 0);
            b.vertices = vertexCount;
            b.packed = b.layer < 3;
            simd_float3 lo = simd_make_float3(INFINITY), hi = simd_make_float3(-INFINITY);
            for (NSUInteger i = 0; i < b.vertices; i++) {
                float v[3], uv[2];
                memcpy(v, data + i * 32, 12);
                memcpy(uv, data + i * 32 + 16, 8);
                simd_float3 position = {v[0], v[1], v[2]};
                lo = simd_min(lo, position);
                hi = simd_max(hi, position);
                if (!isfinite(v[0]) || !isfinite(v[1]) || !isfinite(v[2]) ||
                    simd_any(simd_abs(position) >= 31.99f) || !isfinite(uv[0]) || !isfinite(uv[1]) ||
                    uv[0] < 0 || uv[0] > 1 || uv[1] < 0 || uv[1] > 1)
                    b.packed = NO;
            }
            simd_float3 center = (lo + hi) * 0.5f;
            b.bounds = (simd_float4){center.x, center.y, center.z, simd_length(hi - center)};
            if (b.vertices) {
                b.range = allocate(b.vertices * (b.packed ? 1 : 2));
                if (b.range.location == NSNotFound) {
                    fail(env, @"terrain arena exceeds Metal buffer limit");
                    return;
                }
                uint8_t *destination = (uint8_t *)context.arena.contents + b.range.location * 16;
                if (b.packed) {
                    for (NSUInteger i = 0; i < b.vertices; i++) {
                        const uint8_t *input = data + i * 32;
                        PackedTerrainVertex *out = (PackedTerrainVertex *)(destination + i * 16);
                        float position[3], uv[2];
                        int16_t light[2];
                        memcpy(position, input, 12);
                        memcpy(uv, input + 16, 8);
                        memcpy(light, input + 24, 4);
                        for (int j = 0; j < 3; j++)
                            out->position[j] = (int16_t)lrintf(position[j] * 1024);
                        memcpy(out->color, input + 12, 4);
                        for (int j = 0; j < 2; j++) {
                            out->uv[j] = (uint16_t)lrintf(uv[j] * 65535);
                            out->light[j] = (uint8_t)MAX(0, MIN(255, light[j]));
                        }
                    }
                } else
                    memcpy(destination, data, (size_t)size);
            }
            b.data = nil;
        } else
            b.data = size ? [context.device newBufferWithBytes:data
                                                        length:size
                                                       options:MTLResourceStorageModeShared]
                          : nil;
    }
}
JNIEXPORT void JNICALL Java_mcopt_legacy_DirectNative_deleteBuffer(JNIEnv *env, jclass type,
                                                                   jint identifier) {
    (void)env;
    (void)type;
    @autoreleasepool {
        DirectBuffer *b = context.buffers[@(identifier)];
        if (!b)
            return;
        if (b.terrain && b.layer < 3 && b.vertices)
            context.recordsDirty = YES;
        retire(b.range);
        [context.buffers removeObjectForKey:@(identifier)];
    }
}
JNIEXPORT void JNICALL Java_mcopt_legacy_DirectNative_draw(JNIEnv *env, jclass type, jobject bytes,
                                                           jint first, jint count, jint mode, jint buffer,
                                                           jobject stateBytes) {
    (void)type;
    @autoreleasepool {
        if (context.collectingTerrain && !bytes) {
            DirectBuffer *chunk = context.buffers[@(buffer)];
            if (chunk.terrain) {
                for (NSUInteger start = 0; start < chunk.vertices; start += 64) {
                    TerrainUnit unit = {{(uint32_t)(chunk.range.location + start * (chunk.packed ? 1 : 2)),
                                         (uint32_t)MIN(64, chunk.vertices - start),
                                         (uint32_t)chunk.layer | (chunk.packed ? 0 : 256), 0},
                                        {chunk.x, chunk.y, chunk.z, 0}};
                    [context.terrainUnits appendBytes:&unit length:sizeof unit];
                }
                return;
            }
        }
        const uint8_t *state = (*env)->GetDirectBufferAddress(env, stateBytes);
        const int *p = (const int *)(state + 640);
        if (!colorForTarget(p[0]).image)
            return;
        BOOL hasDepth = depthForTarget(p[0]).image != nil;
        id<MTLRenderPipelineState> pipe = pipeline(env, p, NO, hasDepth);
        if (!pipe)
            return;
        id<MTLBuffer> vertices;
        NSUInteger vertexOffset = 0;
        if (bytes) {
            const void *source = (*env)->GetDirectBufferAddress(env, bytes);
            vertices = stage(source, (NSUInteger)(first + count) * p[24], &vertexOffset);
        } else {
            DirectBuffer *b = context.buffers[@(buffer)];
            vertices = b.terrain ? context.arena : b.data;
            vertexOffset = b.terrain ? b.range.location * 16 : 0;
        }
        if (!vertices)
            return;
        DirectUniforms u = uniforms(state);
        NSUInteger uniformOffset;
        id<MTLBuffer> uniformBuffer = stage(&u, sizeof u, &uniformOffset);
        id<MTLRenderCommandEncoder> e = encoder(p[0]);
        [e setRenderPipelineState:pipe];
        apply(e, state, hasDepth);
        [e setVertexBuffer:vertices offset:vertexOffset atIndex:0];
        [e setVertexBuffer:uniformBuffer offset:uniformOffset atIndex:1];
        uint32_t stride = p[24];
        [e setVertexBytes:&stride length:4 atIndex:2];
        [e setFragmentBuffer:uniformBuffer offset:uniformOffset atIndex:1];
        DirectEffect *effect = context.effects[@(p[26])];
        if (effect) {
            NSUInteger offset;
            id<MTLBuffer> data = stage(effect.uniforms.bytes, effect.uniforms.length, &offset);
            [e setVertexBuffer:data offset:offset atIndex:1];
            [e setFragmentBuffer:data offset:offset atIndex:1];
            const int *units = effect.units.bytes, *ids = (const int *)(state + 768);
            for (NSUInteger i = 0; i < effect.units.length / sizeof(int); i++) {
                int unit = MAX(0, MIN(15, units[i]));
                DirectTexture *t = context.textures[@(ids[unit])] ?: context.white;
                [e setFragmentTexture:t.image ?: context.white.image atIndex:i];
                [e setFragmentSamplerState:sampler(t) atIndex:i];
            }
        }
        if (mode == 7) {
            quadIndices((first + count + 3) / 4);
            [e drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                          indexCount:(count / 4) * 6
                           indexType:MTLIndexTypeUInt32
                         indexBuffer:context.quadIndices
                   indexBufferOffset:(first / 4) * 6 * 4];
        } else if (mode == 2) {
            NSUInteger offset;
            id<MTLBuffer> indices = stage(NULL, (NSUInteger)(count + 1) * 4, &offset);
            uint32_t *output = (uint32_t *)((uint8_t *)indices.contents + offset);
            for (int i = 0; i < count; i++)
                output[i] = first + i;
            output[count] = first;
            [e drawIndexedPrimitives:MTLPrimitiveTypeLineStrip
                          indexCount:count + 1
                           indexType:MTLIndexTypeUInt32
                         indexBuffer:indices
                   indexBufferOffset:offset];
        } else if (mode == 6) {
            if (count < 3)
                return;
            NSUInteger offset;
            id<MTLBuffer> indices = stage(NULL, (count - 2) * 3 * 4, &offset);
            uint32_t *output = (uint32_t *)((uint8_t *)indices.contents + offset);
            for (int i = 0; i < count - 2; i++) {
                output[i * 3] = first;
                output[i * 3 + 1] = first + i + 1;
                output[i * 3 + 2] = first + i + 2;
            }
            [e drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                          indexCount:(count - 2) * 3
                           indexType:MTLIndexTypeUInt32
                         indexBuffer:indices
                   indexBufferOffset:offset];
        } else
            [e drawPrimitives:mode == 0                ? MTLPrimitiveTypePoint
                              : mode == 1              ? MTLPrimitiveTypeLine
                              : mode == 2 || mode == 3 ? MTLPrimitiveTypeLineStrip
                              : mode == 5              ? MTLPrimitiveTypeTriangleStrip
                                                       : MTLPrimitiveTypeTriangle
                  vertexStart:first
                  vertexCount:count];
    }
}
JNIEXPORT void JNICALL Java_mcopt_legacy_DirectNative_terrainOrigin(JNIEnv *env, jclass type, jint identifier,
                                                                    jint layer, jint section, jint x, jint y,
                                                                    jint z) {
    (void)env;
    (void)type;
    @autoreleasepool {
        DirectBuffer *b = context.buffers[@(identifier)];
        if (!b) {
            b = [DirectBuffer new];
            context.buffers[@(identifier)] = b;
        }
        BOOL moved = b.x != x || b.y != y || b.z != z;
        if (b.vertices && ((b.terrain && b.layer < 3) || layer < 3) &&
            (moved || b.layer != layer || b.section != section))
            context.recordsDirty = YES;
        if (b.terrain && moved) {
            retire(b.range);
            b.range = NSMakeRange(0, 0);
            b.vertices = 0;
        }
        b.terrain = YES;
        b.layer = layer;
        b.section = section;
        b.x = x;
        b.y = y;
        b.z = z;
    }
}
JNIEXPORT void JNICALL Java_mcopt_legacy_DirectNative_terrainDraw(JNIEnv *env, jclass type, jint layer,
                                                                  jobject stateBytes, jdouble x, jdouble y,
                                                                  jdouble z, jint distance) {
    (void)type;
    @autoreleasepool {
        rebuildRecords();
        if (!context.recordCount || !context.visibility)
            return;
        const uint8_t *state = (*env)->GetDirectBufferAddress(env, stateBytes);
        const int *p = (const int *)(state + 640);
        BOOL depth = depthForTarget(p[0]).image != nil;
        id<MTLRenderPipelineState> pipe = pipeline(env, p, YES, depth);
        if (!pipe)
            return;
        TerrainFrame f = {0};
        f.uniforms = uniforms(state);
        f.camera = (simd_int4){(int32_t)floor(x), (int32_t)floor(y), (int32_t)floor(z), 0};
        f.offset =
            (simd_float4){(float)(f.camera.x - x), (float)(f.camera.y - y), (float)(f.camera.z - z), 0};
        f.limits =
            (simd_uint4){(uint32_t)context.recordCount, (uint32_t)layer, (uint32_t)distance, (uint32_t)p[10]};
        for (int axis = 0; axis < 3; axis++)
            for (int side = 0; side < 2; side++) {
                float sign = side ? 1 : -1;
                simd_float4 plane;
                for (int c = 0; c < 4; c++)
                    plane[c] =
                        f.uniforms.matrices[0][c * 4 + 3] + sign * f.uniforms.matrices[0][c * 4 + axis];
                float length = simd_length(simd_make_float3(plane));
                f.planes[axis * 2 + side] = plane / MAX(length, 0.000001f);
            }
        NSUInteger offset;
        id<MTLBuffer> frame = stage(&f, sizeof f, &offset);
        DirectFrame *slot = context.frames[context.frameIndex % 3];
        if (slot.unitCapacity < context.unitCount) {
            slot.unitCapacity = MAX(context.unitCount, MAX(4096ULL, slot.unitCapacity * 2));
            slot.units = [context.device newBufferWithLength:slot.unitCapacity * 32
                                                     options:MTLResourceStorageModePrivate];
        }
        uint32_t args[5] = {96, 0, 0, 0, 0};
        NSUInteger argsOffset;
        id<MTLBuffer> arguments = stage(args, sizeof args, &argsOffset);
        endEncoder();
        id<MTLComputeCommandEncoder> compute = [context.command computeCommandEncoder];
        [compute setComputePipelineState:context.cullPipeline];
        [compute setBuffer:context.records offset:0 atIndex:0];
        [compute setBuffer:frame offset:offset atIndex:1];
        [compute setBuffer:context.visibility offset:context.visibilityOffset atIndex:2];
        [compute setBuffer:slot.units offset:0 atIndex:3];
        [compute setBuffer:arguments offset:argsOffset atIndex:4];
        [compute dispatchThreads:MTLSizeMake(context.recordCount, 1, 1)
            threadsPerThreadgroup:MTLSizeMake(64, 1, 1)];
        [compute endEncoding];
        quadIndices(16);
        id<MTLRenderCommandEncoder> e = encoder(p[0]);
        [e setRenderPipelineState:pipe];
        apply(e, state, depth);
        [e setVertexBuffer:context.arena offset:0 atIndex:0];
        [e setVertexBuffer:frame offset:offset atIndex:1];
        [e setVertexBuffer:slot.units offset:0 atIndex:3];
        const int *textures = (const int *)(state + 768);
        DirectTexture *light = context.textures[@(textures[2])] ?: context.white;
        [e setVertexTexture:light.image ?: context.white.image atIndex:0];
        [e setVertexSamplerState:sampler(light) atIndex:0];
        [e setFragmentBuffer:frame offset:offset atIndex:1];
        [e drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                       indexType:MTLIndexTypeUInt32
                     indexBuffer:context.quadIndices
               indexBufferOffset:0
                  indirectBuffer:arguments
            indirectBufferOffset:argsOffset];
    }
}
static id<MTLBuffer> download(id<MTLTexture> texture, int level, int x, int y, int width, int height,
                              NSUInteger *rowBytes) {
    begin();
    endEncoder();
    *rowBytes = ((NSUInteger)width * 4 + 255) & ~255ULL;
    id<MTLBuffer> result = [context.device newBufferWithLength:*rowBytes * height
                                                       options:MTLResourceStorageModeShared];
    id<MTLBlitCommandEncoder> e = [context.command blitCommandEncoder];
    [e copyFromTexture:texture
                     sourceSlice:0
                     sourceLevel:level
                    sourceOrigin:MTLOriginMake(x, y, 0)
                      sourceSize:MTLSizeMake(width, height, 1)
                        toBuffer:result
               destinationOffset:0
          destinationBytesPerRow:*rowBytes
        destinationBytesPerImage:*rowBytes * height];
    [e endEncoding];
    [context.command commit];
    [context.command waitUntilCompleted];
    context.lastSubmission = context.command;
    context.command = nil;
    return result;
}
static int readbackComponents(int format) {
    switch (format) {
    case 6408:
    case 32993:
        return 4;
    case 6407:
        return 3;
    case 33319:
    case 6410:
        return 2;
    case 6402:
    case 6403:
    case 6406:
    case 6409:
        return 1;
    default:
        return 0;
    }
}
static void packReadback(const uint8_t *input, NSUInteger stride, int width, int height, int format, int type,
                         BOOL depth, uint8_t *output) {
    int count = readbackComponents(format), componentSize = type == 5126 ? 4 : 1;
    for (int y = 0; y < height; y++) {
        if (format == 6408 && type == 5121 && !depth) {
            memcpy(output + (NSUInteger)y * width * 4, input + (NSUInteger)y * stride, (NSUInteger)width * 4);
            continue;
        }
        for (int x = 0; x < width; x++) {
            const uint8_t *pixel = input + (NSUInteger)y * stride + (NSUInteger)x * 4;
            float rgba[4];
            if (depth) {
                memcpy(&rgba[0], pixel, 4);
                rgba[1] = rgba[2] = 0;
                rgba[3] = 1;
            } else
                for (int i = 0; i < 4; i++)
                    rgba[i] = pixel[i] / 255.0f;
            for (int channel = 0; channel < count; channel++) {
                int source = format == 6406                   ? 3
                             : format == 6410 && channel == 1 ? 3
                             : format == 32993 && channel < 3 ? 2 - channel
                                                              : channel;
                uint8_t *destination =
                    output +
                    ((NSUInteger)y * width * count + (NSUInteger)x * count + channel) * componentSize;
                if (type == 5126)
                    memcpy(destination, &rgba[source], 4);
                else
                    *destination = (uint8_t)lrintf(fminf(1, fmaxf(0, rgba[source])) * 255);
            }
        }
    }
}
JNIEXPORT void JNICALL Java_mcopt_legacy_DirectNative_readTexture(JNIEnv *env, jclass owner, jint identifier,
                                                                  jint level, jint format, jint type,
                                                                  jlong address) {
    (void)owner;
    @autoreleasepool {
        DirectTexture *texture = context.textures[@(identifier)];
        if (!texture.image)
            return;
        if (!readbackComponents(format) || (type != 5121 && type != 5126) || level < 0 ||
            (NSUInteger)level >= texture.image.mipmapLevelCount) {
            fail(env, @"unsupported texture readback format or mip level");
            return;
        }
        int width = MAX(1, (int)texture.image.width >> level),
            height = MAX(1, (int)texture.image.height >> level);
        NSUInteger stride;
        id<MTLBuffer> data = download(texture.image, level, 0, 0, width, height, &stride);
        packReadback(data.contents, stride, width, height, format, type,
                     texture.image.pixelFormat == MTLPixelFormatDepth32Float, (uint8_t *)(intptr_t)address);
    }
}
JNIEXPORT void JNICALL Java_mcopt_legacy_DirectNative_readPixels(JNIEnv *env, jclass owner, jint target,
                                                                 jint x, jint y, jint width, jint height,
                                                                 jint format, jint type, jlong address) {
    (void)owner;
    @autoreleasepool {
        if (width <= 0 || height <= 0)
            return;
        id<MTLTexture> texture = format == 6402 ? depthForTarget(target).image : colorForTarget(target).image;
        if (!texture || !readbackComponents(format) || (type != 5121 && type != 5126) || x < 0 || y < 0 ||
            x + width > (int)texture.width || y + height > (int)texture.height) {
            fail(env, @"unsupported framebuffer readback region or format");
            return;
        }
        NSUInteger stride;
        id<MTLBuffer> data = download(texture, 0, x, y, width, height, &stride);
        packReadback(data.contents, stride, width, height, format, type,
                     texture.pixelFormat == MTLPixelFormatDepth32Float, (uint8_t *)(intptr_t)address);
    }
}
JNIEXPORT void JNICALL Java_mcopt_legacy_DirectNative_copyDepth(JNIEnv *env, jclass type, jint source,
                                                                jint destination) {
    (void)env;
    (void)type;
    @autoreleasepool {
        id<MTLTexture> a = depthForTarget(source).image, b = depthForTarget(destination).image;
        if (!a || !b)
            return;
        begin();
        endEncoder();
        id<MTLBlitCommandEncoder> e = [context.command blitCommandEncoder];
        [e copyFromTexture:a
                  sourceSlice:0
                  sourceLevel:0
                 sourceOrigin:MTLOriginMake(0, 0, 0)
                   sourceSize:MTLSizeMake(MIN(a.width, b.width), MIN(a.height, b.height), 1)
                    toTexture:b
             destinationSlice:0
             destinationLevel:0
            destinationOrigin:MTLOriginMake(0, 0, 0)];
        [e endEncoding];
    }
}

static NSString *javaString(JNIEnv *env, jstring value) {
    const char *bytes = (*env)->GetStringUTFChars(env, value, NULL);
    NSString *result = [NSString stringWithUTF8String:bytes];
    (*env)->ReleaseStringUTFChars(env, value, bytes);
    return result;
}
JNIEXPORT void JNICALL Java_mcopt_legacy_DirectNative_effect(JNIEnv *env, jclass type, jint identifier,
                                                             jstring vertex, jstring fragment,
                                                             jstring vertexEntry, jstring fragmentEntry) {
    (void)type;
    @autoreleasepool {
        NSError *error = nil;
        MTLCompileOptions *options = [MTLCompileOptions new];
        options.languageVersion = MTLLanguageVersion3_0;
        id<MTLLibrary> vs = [context.device newLibraryWithSource:javaString(env, vertex)
                                                         options:options
                                                           error:&error];
        if (!vs) {
            fail(env, error.description);
            return;
        }
        id<MTLLibrary> fs = [context.device newLibraryWithSource:javaString(env, fragment)
                                                         options:options
                                                           error:&error];
        if (!fs) {
            fail(env, error.description);
            return;
        }
        DirectEffect *effect = [DirectEffect new];
        effect.vertex = [vs newFunctionWithName:javaString(env, vertexEntry)];
        effect.fragment = [fs newFunctionWithName:javaString(env, fragmentEntry)];
        context.effects[@(identifier)] = effect;
    }
}
JNIEXPORT void JNICALL Java_mcopt_legacy_DirectNative_effectData(JNIEnv *env, jclass type, jint identifier,
                                                                 jobject bytes, jintArray units) {
    (void)type;
    @autoreleasepool {
        DirectEffect *effect = context.effects[@(identifier)];
        effect.uniforms = [NSData dataWithBytes:(*env)->GetDirectBufferAddress(env, bytes)
                                         length:(NSUInteger)(*env)->GetDirectBufferCapacity(env, bytes)];
        jsize count = (*env)->GetArrayLength(env, units);
        NSMutableData *values = [NSMutableData dataWithLength:count * sizeof(jint)];
        (*env)->GetIntArrayRegion(env, units, 0, count, values.mutableBytes);
        effect.units = values;
    }
}
JNIEXPORT void JNICALL Java_mcopt_legacy_DirectNative_deleteEffect(JNIEnv *env, jclass type,
                                                                   jint identifier) {
    (void)env;
    (void)type;
    @autoreleasepool {
        [context.effects removeObjectForKey:@(identifier)];
    }
}

JNIEXPORT void JNICALL Java_mcopt_legacy_DirectNative_terrainVisibility(JNIEnv *env, jclass type,
                                                                        jobject bytes, jint words) {
    (void)type;
    @autoreleasepool {
        NSUInteger offset;
        context.visibility =
            stage((*env)->GetDirectBufferAddress(env, bytes), (NSUInteger)words * 4, &offset);
        context.visibilityOffset = offset;
    }
}

JNIEXPORT jdoubleArray JNICALL Java_mcopt_legacy_DirectNative_frameStats(JNIEnv *env, jclass type) {
    (void)type;
    double values[] = {context.gpuMilliseconds, context.fenceMilliseconds,
                       (double)context.arenaCapacity * 16 / 1048576.0, (double)context.recordCount};
    jdoubleArray result = (*env)->NewDoubleArray(env, 4);
    (*env)->SetDoubleArrayRegion(env, result, 0, 4, values);
    return result;
}

JNIEXPORT void JNICALL Java_mcopt_legacy_DirectNative_beginTerrainBatch(JNIEnv *env, jclass type,
                                                                        jobject state, jdouble x, jdouble y,
                                                                        jdouble z) {
    (void)type;
    @autoreleasepool {
        context.terrainState = [NSData dataWithBytes:(*env)->GetDirectBufferAddress(env, state) length:1024];
        context.terrainCamera = (simd_double3){x, y, z};
        context.terrainUnits = [NSMutableData new];
        context.collectingTerrain = YES;
    }
}
JNIEXPORT void JNICALL Java_mcopt_legacy_DirectNative_endTerrainBatch(JNIEnv *env, jclass type) {
    (void)type;
    @autoreleasepool {
        context.collectingTerrain = NO;
        if (!context.terrainUnits.length)
            return;
        const uint8_t *state = context.terrainState.bytes;
        const int *p = (const int *)(state + 640);
        BOOL depth = depthForTarget(p[0]).image != nil;
        id<MTLRenderPipelineState> pipe = pipeline(env, p, YES, depth);
        if (!pipe)
            return;
        TerrainFrame f = {0};
        f.uniforms = uniforms(state);
        simd_double3 camera = context.terrainCamera;
        f.camera =
            (simd_int4){(int32_t)floor(camera.x), (int32_t)floor(camera.y), (int32_t)floor(camera.z), 0};
        f.offset = (simd_float4){(float)(f.camera.x - camera.x), (float)(f.camera.y - camera.y),
                                 (float)(f.camera.z - camera.z), 0};
        NSUInteger frameOffset, unitOffset;
        id<MTLBuffer> frame = stage(&f, sizeof f, &frameOffset),
                      units = stage(context.terrainUnits.bytes, context.terrainUnits.length, &unitOffset);
        quadIndices(16);
        id<MTLRenderCommandEncoder> e = encoder(p[0]);
        [e setRenderPipelineState:pipe];
        apply(e, state, depth);
        [e setVertexBuffer:context.arena offset:0 atIndex:0];
        [e setVertexBuffer:frame offset:frameOffset atIndex:1];
        [e setVertexBuffer:units offset:unitOffset atIndex:3];
        [e setFragmentBuffer:frame offset:frameOffset atIndex:1];
        const int *textures = (const int *)(state + 768);
        DirectTexture *light = context.textures[@(textures[2])] ?: context.white;
        [e setVertexTexture:light.image ?: context.white.image atIndex:0];
        [e setVertexSamplerState:sampler(light) atIndex:0];
        [e drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                      indexCount:96
                       indexType:MTLIndexTypeUInt32
                     indexBuffer:context.quadIndices
               indexBufferOffset:0
                   instanceCount:context.terrainUnits.length / sizeof(TerrainUnit)];
        context.terrainUnits = nil;
        context.terrainState = nil;
    }
}
