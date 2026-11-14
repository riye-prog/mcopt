#define VK_USE_PLATFORM_METAL_EXT
#import <AppKit/AppKit.h>
#import <QuartzCore/CAMetalLayer.h>
#include <vulkan/vulkan.h>
#include <jni.h>
#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <deque>
#include <limits>
#include <map>
#include <memory>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <vector>
#include "vulkan_shaders.h"
#include "terrainmesh.h"

namespace {
constexpr VkFormat colorFormat = VK_FORMAT_R8G8B8A8_UNORM;
constexpr VkFormat depthFormat = VK_FORMAT_D32_SFLOAT;
constexpr uint32_t framesInFlight = 2;
constexpr uint64_t fenceTimeout = 2'000'000'000;
constexpr uint64_t acquireTimeout = 4'000'000;
constexpr uint32_t maxTextures = 8;
constexpr VkDeviceSize stageSize = 8 * 1024 * 1024;
constexpr VkDeviceSize stateSize = 592;
constexpr uint32_t unitsBinding = maxTextures + 2;
constexpr std::array<uint32_t, 3> chunkUnitWidths{8, 24, 64};

void check(VkResult result, const char *operation) {
    if (result != VK_SUCCESS) {
        throw std::runtime_error(std::string(operation) + " failed (" + std::to_string(result) + ")");
    }
}

void fail(JNIEnv *env, const std::exception &error) {
    jclass type = env->FindClass("java/lang/IllegalStateException");
    if (type) env->ThrowNew(type, error.what());
}

template<class Function> void nativeCall(JNIEnv *env, Function &&function) {
    if (env->ExceptionCheck()) return;
    try {
        function();
    } catch (const std::exception &error) {
        fail(env, error);
    }
}

uint32_t mipSize(uint32_t size, uint32_t level) {
    return std::max(1u, size >> level);
}
struct Buffer {
    VkDevice device;
    VkBuffer handle = VK_NULL_HANDLE;
    VkDeviceMemory memory = VK_NULL_HANDLE;
    uint8_t *data = nullptr;
    VkDeviceSize size;
    VkDeviceSize used = 0;

    Buffer(VkDevice device, VkDeviceSize size) : device(device), size(size) {}
    ~Buffer() {
        if (data) vkUnmapMemory(device, memory);
        if (handle) vkDestroyBuffer(device, handle, nullptr);
        if (memory) vkFreeMemory(device, memory, nullptr);
    }
};

struct Image {
    VkDevice device;
    VkImage handle = VK_NULL_HANDLE;
    VkDeviceMemory memory = VK_NULL_HANDLE;
    VkImageView attachment = VK_NULL_HANDLE;
    VkImageView sample = VK_NULL_HANDLE;
    VkImageLayout layout = VK_IMAGE_LAYOUT_UNDEFINED;
    uint32_t width;
    uint32_t height;
    uint32_t levels;
    VkImageAspectFlags aspect;
    bool inverted = false;

    Image(VkDevice device, uint32_t width, uint32_t height, uint32_t levels, bool depth)
        : device(device), width(width), height(height), levels(levels),
          aspect(depth ? VK_IMAGE_ASPECT_DEPTH_BIT : VK_IMAGE_ASPECT_COLOR_BIT) {}
    ~Image() {
        if (sample && sample != attachment) vkDestroyImageView(device, sample, nullptr);
        if (attachment) vkDestroyImageView(device, attachment, nullptr);
        if (handle) vkDestroyImage(device, handle, nullptr);
        if (memory) vkFreeMemory(device, memory, nullptr);
    }
};

struct Texture {
    std::shared_ptr<Image> image;
    int min = 9728;
    int mag = 9728;
    int wrapS = 10497;
    int wrapT = 10497;
    int maxLevel = 0;
};

struct Target {
    int color = 0;
    int depth = 0;
};

struct TerrainPage {
    std::shared_ptr<Buffer> buffer;
    std::map<VkDeviceSize, VkDeviceSize> available;
    bool translucent = false;
    VkDeviceSize largestRange = 0;
};
struct TerrainRange {
    TerrainPage *page = nullptr;
    VkDeviceSize offset = 0;
    VkDeviceSize length = 0;
    VkDeviceSize reserved = 0;
};
struct RetiredRange {
    TerrainRange range;
    uint64_t submission;
};
struct Mesh {
    std::shared_ptr<Buffer> buffer;
    TerrainRange range;
    terrainmesh::Result geometry;
    bool terrain = false;
    int layer = 0;
    std::array<int, 3> origin{};
};
struct DistantMesh {
    TerrainRange range;
    int x;
    int z;
    float minY;
    float maxY;
};
struct ChunkUnit {
    std::array<float, 3> translation;
    uint32_t first;
    uint32_t count;
    uint32_t padding[3]{};
};
static_assert(sizeof(ChunkUnit) == 32);

struct Effect {
    VkShaderModule vertex = VK_NULL_HANDLE;
    VkShaderModule fragment = VK_NULL_HANDLE;
    std::vector<uint8_t> uniforms;
    std::vector<int> units;
};

struct Frame {
    VkCommandPool commands = VK_NULL_HANDLE;
    VkCommandBuffer command = VK_NULL_HANDLE;
    VkFence fence = VK_NULL_HANDLE;
    VkSemaphore acquire = VK_NULL_HANDLE;
    bool pending = false;
    std::vector<VkDescriptorPool> descriptors;
    size_t descriptorIndex = 0;
    uint32_t descriptorCount = 0;
    std::vector<std::shared_ptr<Buffer>> pages;
    std::vector<std::shared_ptr<Buffer>> buffers;
    std::vector<std::shared_ptr<Image>> images;
};

struct Slice {
    VkBuffer buffer;
    VkDeviceSize offset;
    uint8_t *data;
};

struct ShaderBytes {
    const uint32_t *words;
    size_t size;
};

struct Geometry {
    std::array<float, 4> translation{};
    uint32_t stride = 0;
};

struct DrawState {
    const uint8_t *bytes;
    const int *pipeline;
    const int *textures;

    explicit DrawState(const void *data) : bytes(static_cast<const uint8_t *>(data)),
        pipeline(reinterpret_cast<const int *>(bytes + 640)),
        textures(reinterpret_cast<const int *>(bytes + 768)) {}
};

struct DrawBindings {
    Slice uniform;
    VkDeviceSize uniformSize;
    std::array<Texture *, maxTextures> sampled;
};
using PipelineKey = std::array<int, 17>;

class Renderer {
public:
    VkInstance instance = VK_NULL_HANDLE;
    VkPhysicalDevice physical = VK_NULL_HANDLE;
    VkDevice device = VK_NULL_HANDLE;
    VkSurfaceKHR surface = VK_NULL_HANDLE;
    VkQueue queue = VK_NULL_HANDLE;
    uint32_t family = 0;
    VkPhysicalDeviceProperties properties{};
    VkPhysicalDeviceMemoryProperties memory{};
    VkSwapchainKHR swapchain = VK_NULL_HANDLE;
    CAMetalLayer *windowLayer = nil;
    VkExtent2D extent{};
    VkExtent2D windowExtent{};
    std::vector<VkImage> swapImages;
    std::vector<VkSemaphore> presented;
    std::vector<bool> initializedImages;
    std::array<Frame, framesInFlight> frames;
    uint64_t submission = 0;
    Frame *recording = nullptr;
    VkImage activeColor = VK_NULL_HANDLE;
    VkImage activeDepth = VK_NULL_HANDLE;
    VkDescriptorSetLayout descriptorLayout = VK_NULL_HANDLE;
    VkPipelineLayout pipelineLayout = VK_NULL_HANDLE;
    VkPipelineCache pipelineCache = VK_NULL_HANDLE;
    VkShaderModule vertex = VK_NULL_HANDLE;
    VkShaderModule fragment = VK_NULL_HANDLE;
    VkShaderModule chunkVertex = VK_NULL_HANDLE;
    VkShaderModule chunkFragment = VK_NULL_HANDLE;
    std::map<PipelineKey, VkPipeline> pipelines;
    VkPipeline boundPipeline = VK_NULL_HANDLE;
    bool logicOps = false;
    std::map<std::array<int, 6>, VkSampler> samplers;
    std::unordered_map<int, Texture> textures;
    std::unordered_map<int, Target> targets;
    std::unordered_map<int, Mesh> meshes;
    std::unordered_map<int, DistantMesh> distantMeshes;
    std::map<TerrainPage *, std::vector<ChunkUnit>> distantUnits;
    std::vector<std::unique_ptr<TerrainPage>> terrainPages;
    std::deque<RetiredRange> retiredTerrain;
    std::map<TerrainPage *, std::array<std::vector<ChunkUnit>, chunkUnitWidths.size()>> visibleTerrain;
    std::vector<ChunkUnit> sortedTerrain;
    bool greedyTerrain = true;
    uint64_t sourceTerrainVertices = 0;
    uint64_t savedTerrainVertices = 0;
    uint64_t terrainCommands = 0;
    std::unordered_map<int, Effect> effects;
    std::vector<VkShaderModule> effectModules;
    std::array<std::vector<int>, 4> visibility;
    std::shared_ptr<Image> screen;
    std::shared_ptr<Image> screenDepth;
    int presentTarget = 0;
    Texture white;
    std::shared_ptr<Buffer> quadIndices;
    uint32_t quadCapacity = 0;
    bool vsync = true;
    bool recreateSwapchain = false;
    double fenceMilliseconds = 0;
    uint64_t presentedFrames = 0;
    uint64_t missedAcquires = 0;
    bool displayTiming = false;
    bool measureDisplay = false;
    uint32_t nextPresentId = 1;
    uint32_t lastMeasuredPresentId = 0;
    uint64_t actualPresents = 0;
    uint64_t lastPresentedAt = 0;
    std::vector<VkPastPresentationTimingGOOGLE> presentationTimings;
    size_t terrainCount = 0;

    ~Renderer();
    void initialize(CAMetalLayer *layer);
    void resetSwapchain(uint32_t width, uint32_t height, bool synchronize);
    uint32_t memoryType(uint32_t bits, VkMemoryPropertyFlags flags) const;
    std::shared_ptr<Buffer> buffer(VkDeviceSize size, VkBufferUsageFlags usage);
    std::shared_ptr<Image> image(uint32_t width, uint32_t height, uint32_t levels, bool depth);
    VkShaderModule shader(ShaderBytes code);
    VkShaderModule shader(const uint8_t *bytes, size_t size);
    Frame &begin();
    void waitForFrame(Frame &frame, const char *operation);
    bool readyToClose() const;
    void endRendering();
    void submit(VkSemaphore wait = VK_NULL_HANDLE, VkSemaphore signal = VK_NULL_HANDLE, bool synchronous = false);
    Slice stage(const void *bytes, VkDeviceSize size, VkDeviceSize alignment = 4);
    void transition(Image &image, VkImageLayout layout);
    void barrier(VkImage image, VkImageAspectFlags aspect, uint32_t levels,
                 VkImageLayout before, VkImageLayout after);
    std::shared_ptr<Image> color(int target);
    std::shared_ptr<Image> depth(int target);
    void renderTo(const std::shared_ptr<Image> &color, const std::shared_ptr<Image> &depth,
                  int clearMask = 0, VkClearColorValue clearColor = {}, float clearDepth = 1.0f);
    void clear(int target, int mask, VkClearColorValue color, float depth);
    VkSampler sampler(const Texture &texture);
    VkPipeline pipeline(const DrawState &state, VkPrimitiveTopology topology, bool depth, uint32_t textureFlags,
                        bool chunk);
    VkDescriptorSet descriptor(Slice uniforms, Slice vertices, VkDeviceSize uniformSize,
                               VkDeviceSize vertexSize, const std::array<Texture *, maxTextures> &sampled,
                               const Slice *units = nullptr, VkDeviceSize unitSize = 0);
    DrawBindings bindDraw(const DrawState &state, int mode, const std::shared_ptr<Image> &destination,
                          bool chunk = false);
    void draw(const void *source, int first, int count, int mode, int mesh,
              const DrawState &state, const Geometry &geometry = {});
    TerrainRange storeTerrain(const void *source, VkDeviceSize size, bool translucent);
    void commitTerrain(Mesh &mesh, const void *source, VkDeviceSize sourceSize, const terrainmesh::Result &geometry);
    void uploadTerrain(Mesh &mesh, const void *source, VkDeviceSize size);
    void retireTerrain(TerrainRange &range);
    void retireTerrain(Mesh &mesh);
    void reclaimTerrain();
    void terrain(int layer, const DrawState &state, double x, double y, double z, int distance);
    void distant(const DrawState &state, const int32_t *columns, int count, double x, double y, double z);
    void submitUnits(TerrainPage &page, const std::vector<ChunkUnit> &units, uint32_t width, const DrawBindings &bindings);
    void upload(Image &image, uint32_t level, int x, int y, int width, int height,
                int rowBytes, int format, const uint8_t *source);
    void copyDepth(int source, int destination);
    void download(Image &image, int level, int x, int y, int width, int height, int format, int type, uint8_t *output);
    void present(int width, int height, bool synchronize);
    void collectPresentationTiming();
    void indices(uint32_t quads);
};

std::unique_ptr<Renderer> renderer;

Renderer &gpu() {
    if (!renderer) throw std::runtime_error("Vulkan renderer is unavailable");
    return *renderer;
}

Renderer::~Renderer() {
    if (device) {
        vkDeviceWaitIdle(device);
        recording = nullptr;
        for (Frame &frame : frames) {
            for (auto pool : frame.descriptors) vkDestroyDescriptorPool(device, pool, nullptr);
            if (frame.commands) vkDestroyCommandPool(device, frame.commands, nullptr);
            if (frame.fence) vkDestroyFence(device, frame.fence, nullptr);
            if (frame.acquire) vkDestroySemaphore(device, frame.acquire, nullptr);
            frame.pages.clear();
            frame.buffers.clear();
            frame.images.clear();
        }
        for (auto entry : pipelines) vkDestroyPipeline(device, entry.second, nullptr);
        for (auto entry : samplers) vkDestroySampler(device, entry.second, nullptr);
        for (auto module : effectModules) vkDestroyShaderModule(device, module, nullptr);
        if (vertex) vkDestroyShaderModule(device, vertex, nullptr);
        if (fragment) vkDestroyShaderModule(device, fragment, nullptr);
        if (chunkVertex) vkDestroyShaderModule(device, chunkVertex, nullptr);
        if (chunkFragment) vkDestroyShaderModule(device, chunkFragment, nullptr);
        if (pipelineCache) vkDestroyPipelineCache(device, pipelineCache, nullptr);
        if (pipelineLayout) vkDestroyPipelineLayout(device, pipelineLayout, nullptr);
        if (descriptorLayout) vkDestroyDescriptorSetLayout(device, descriptorLayout, nullptr);
        white.image.reset();
        screen.reset();
        screenDepth.reset();
        textures.clear();
        meshes.clear();
        terrainPages.clear();
        quadIndices.reset();
        for (auto semaphore : presented) vkDestroySemaphore(device, semaphore, nullptr);
        if (swapchain) vkDestroySwapchainKHR(device, swapchain, nullptr);
        vkDestroyDevice(device, nullptr);
    }
    if (surface) vkDestroySurfaceKHR(instance, surface, nullptr);
    if (instance) vkDestroyInstance(instance, nullptr);
}

void Renderer::initialize(CAMetalLayer *layer) {
    windowLayer = layer;
    const char *extensions[] = {VK_KHR_SURFACE_EXTENSION_NAME, VK_EXT_METAL_SURFACE_EXTENSION_NAME};
    VkApplicationInfo app{VK_STRUCTURE_TYPE_APPLICATION_INFO};
    app.pApplicationName = "Meshnet Vulkan";
    app.apiVersion = VK_API_VERSION_1_3;
    VkInstanceCreateInfo create{VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO};
    create.pApplicationInfo = &app;
    create.enabledExtensionCount = 2;
    create.ppEnabledExtensionNames = extensions;
    check(vkCreateInstance(&create, nullptr, &instance), "Creating Vulkan instance");

    VkMetalSurfaceCreateInfoEXT createSurface{VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT};
    createSurface.pLayer = layer;
    check(vkCreateMetalSurfaceEXT(instance, &createSurface, nullptr, &surface), "Creating Vulkan window surface");

    uint32_t count = 0;
    check(vkEnumeratePhysicalDevices(instance, &count, nullptr), "Enumerating Vulkan devices");
    std::vector<VkPhysicalDevice> devices(count);
    check(vkEnumeratePhysicalDevices(instance, &count, devices.data()), "Reading Vulkan devices");
    for (auto candidate : devices) {
        uint32_t queueCount = 0;
        vkGetPhysicalDeviceQueueFamilyProperties(candidate, &queueCount, nullptr);
        std::vector<VkQueueFamilyProperties> queues(queueCount);
        vkGetPhysicalDeviceQueueFamilyProperties(candidate, &queueCount, queues.data());
        for (uint32_t index = 0; index < queueCount; index++) {
            VkBool32 supported = VK_FALSE;
            check(vkGetPhysicalDeviceSurfaceSupportKHR(candidate, index, surface, &supported), "Checking Vulkan surface support");
            if (supported && (queues[index].queueFlags & VK_QUEUE_GRAPHICS_BIT)) {
                physical = candidate;
                family = index;
                break;
            }
        }
        if (physical) break;
    }
    if (!physical) throw std::runtime_error("No Vulkan graphics queue supports the Minecraft window");
    vkGetPhysicalDeviceProperties(physical, &properties);
    vkGetPhysicalDeviceMemoryProperties(physical, &memory);
    VkPhysicalDeviceDynamicRenderingFeatures dynamic{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DYNAMIC_RENDERING_FEATURES};
    VkPhysicalDeviceFeatures2 features{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2};
    features.pNext = &dynamic;
    vkGetPhysicalDeviceFeatures2(physical, &features);
    if (!dynamic.dynamicRendering) throw std::runtime_error("Vulkan dynamic rendering is unavailable");

    float priority = 1.0f;
    VkDeviceQueueCreateInfo queueInfo{VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO};
    queueInfo.queueFamilyIndex = family;
    queueInfo.queueCount = 1;
    queueInfo.pQueuePriorities = &priority;
    VkPhysicalDeviceFeatures enabled{};
    enabled.logicOp = features.features.logicOp;
    logicOps = enabled.logicOp;
    std::vector<const char *> deviceExtensions{VK_KHR_SWAPCHAIN_EXTENSION_NAME, "VK_KHR_portability_subset",
                                              VK_KHR_DYNAMIC_RENDERING_EXTENSION_NAME};
    check(vkEnumerateDeviceExtensionProperties(physical, nullptr, &count, nullptr), "Counting Vulkan device extensions");
    std::vector<VkExtensionProperties> availableExtensions(count);
    check(vkEnumerateDeviceExtensionProperties(physical, nullptr, &count, availableExtensions.data()),
        "Reading Vulkan device extensions");
    for (const auto &extension : availableExtensions) {
        if (measureDisplay && std::strcmp(extension.extensionName, VK_GOOGLE_DISPLAY_TIMING_EXTENSION_NAME) == 0) {
            displayTiming = true;
            deviceExtensions.push_back(VK_GOOGLE_DISPLAY_TIMING_EXTENSION_NAME);
            break;
        }
    }
    VkDeviceCreateInfo deviceInfo{VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO};
    deviceInfo.pNext = &dynamic;
    deviceInfo.queueCreateInfoCount = 1;
    deviceInfo.pQueueCreateInfos = &queueInfo;
    deviceInfo.enabledExtensionCount = deviceExtensions.size();
    deviceInfo.ppEnabledExtensionNames = deviceExtensions.data();
    deviceInfo.pEnabledFeatures = &enabled;
    check(vkCreateDevice(physical, &deviceInfo, nullptr, &device), "Creating Vulkan device");
    vkGetDeviceQueue(device, family, 0, &queue);

    std::array<VkDescriptorSetLayoutBinding, maxTextures + 3> bindings{};
    bindings[0] = {0, VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, 1, VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT, nullptr};
    bindings[1] = {1, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1, VK_SHADER_STAGE_VERTEX_BIT, nullptr};
    for (uint32_t index = 0; index < maxTextures; index++) {
        bindings[index + 2] = {index + 2, VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, 1, VK_SHADER_STAGE_FRAGMENT_BIT, nullptr};
    }
    bindings[unitsBinding] = {unitsBinding, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1, VK_SHADER_STAGE_VERTEX_BIT, nullptr};
    VkDescriptorSetLayoutCreateInfo descriptorInfo{VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO};
    descriptorInfo.bindingCount = bindings.size();
    descriptorInfo.pBindings = bindings.data();
    check(vkCreateDescriptorSetLayout(device, &descriptorInfo, nullptr, &descriptorLayout), "Creating Vulkan descriptor layout");
    VkPushConstantRange geometry{VK_SHADER_STAGE_VERTEX_BIT, 0, sizeof(Geometry)};
    VkPipelineLayoutCreateInfo layout{VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO};
    layout.setLayoutCount = 1;
    layout.pSetLayouts = &descriptorLayout;
    layout.pushConstantRangeCount = 1;
    layout.pPushConstantRanges = &geometry;
    check(vkCreatePipelineLayout(device, &layout, nullptr, &pipelineLayout), "Creating Vulkan pipeline layout");
    VkPipelineCacheCreateInfo cacheInfo{VK_STRUCTURE_TYPE_PIPELINE_CACHE_CREATE_INFO};
    check(vkCreatePipelineCache(device, &cacheInfo, nullptr, &pipelineCache), "Creating Vulkan pipeline cache");
    vertex = shader({terrain_vert, sizeof(terrain_vert)});
    fragment = shader({terrain_frag, sizeof(terrain_frag)});
    chunkVertex = shader({chunk_vert, sizeof(chunk_vert)});
    chunkFragment = shader({chunk_frag, sizeof(chunk_frag)});

    for (Frame &frame : frames) {
        VkFenceCreateInfo fence{VK_STRUCTURE_TYPE_FENCE_CREATE_INFO};
        fence.flags = VK_FENCE_CREATE_SIGNALED_BIT;
        check(vkCreateFence(device, &fence, nullptr, &frame.fence), "Creating Vulkan frame fence");
        VkSemaphoreCreateInfo semaphore{VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO};
        check(vkCreateSemaphore(device, &semaphore, nullptr, &frame.acquire), "Creating Vulkan acquire semaphore");
        VkCommandPoolCreateInfo pool{VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO};
        pool.queueFamilyIndex = family;
        check(vkCreateCommandPool(device, &pool, nullptr, &frame.commands), "Creating Vulkan command pool");
        VkCommandBufferAllocateInfo command{VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO};
        command.commandPool = frame.commands;
        command.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
        command.commandBufferCount = 1;
        check(vkAllocateCommandBuffers(device, &command, &frame.command), "Allocating Vulkan frame commands");
    }

    VkSurfaceCapabilitiesKHR support{};
    check(vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physical, surface, &support), "Reading Vulkan window footprint");
    auto size = support.currentExtent;
    resetSwapchain(size.width == UINT32_MAX ? 854 : size.width, size.height == UINT32_MAX ? 480 : size.height, true);
    white.image = image(1, 1, 1, false);
    const uint8_t pixel[] = {255, 255, 255, 255};
    upload(*white.image, 0, 0, 0, 1, 1, 4, 6408, pixel);
}

void Renderer::resetSwapchain(uint32_t width, uint32_t height, bool synchronize) {
    windowExtent = {width, height};
    windowLayer.drawableSize = CGSizeMake(width, height);
    VkSurfaceCapabilitiesKHR capabilities{};
    check(vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physical, surface, &capabilities), "Reading Vulkan surface capabilities");
    if (capabilities.currentExtent.width != UINT32_MAX) {
        width = capabilities.currentExtent.width;
        height = capabilities.currentExtent.height;
    } else {
        width = std::clamp(width, capabilities.minImageExtent.width, capabilities.maxImageExtent.width);
        height = std::clamp(height, capabilities.minImageExtent.height, capabilities.maxImageExtent.height);
    }
    if (!width || !height) return;
    uint32_t count = 0;
    check(vkGetPhysicalDeviceSurfaceFormatsKHR(physical, surface, &count, nullptr), "Enumerating Vulkan surface formats");
    std::vector<VkSurfaceFormatKHR> formats(count);
    check(vkGetPhysicalDeviceSurfaceFormatsKHR(physical, surface, &count, formats.data()), "Reading Vulkan surface formats");
    if (formats.empty()) throw std::runtime_error("No Vulkan surface format");
    VkSurfaceFormatKHR format = formats.front();
    for (auto entry : formats) {
        if (entry.format == VK_FORMAT_B8G8R8A8_UNORM) {
            format = entry;
            break;
        }
    }
    check(vkGetPhysicalDeviceSurfacePresentModesKHR(physical, surface, &count, nullptr), "Enumerating Vulkan present modes");
    std::vector<VkPresentModeKHR> modes(count);
    check(vkGetPhysicalDeviceSurfacePresentModesKHR(physical, surface, &count, modes.data()), "Reading Vulkan present modes");
    VkPresentModeKHR mode = VK_PRESENT_MODE_FIFO_KHR;
    if (!synchronize) {
        if (std::find(modes.begin(), modes.end(), VK_PRESENT_MODE_MAILBOX_KHR) != modes.end()) {
            mode = VK_PRESENT_MODE_MAILBOX_KHR;
        }
    }
    if (!(capabilities.supportedUsageFlags & VK_IMAGE_USAGE_TRANSFER_DST_BIT)) {
        throw std::runtime_error("Vulkan swapchain cannot receive the Minecraft framebuffer");
    }
    VkSwapchainCreateInfoKHR create{VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR};
    create.surface = surface;
    create.minImageCount = std::max(capabilities.minImageCount, framesInFlight + 1);
    if (capabilities.maxImageCount) create.minImageCount = std::min(create.minImageCount, capabilities.maxImageCount);
    create.imageFormat = format.format;
    create.imageColorSpace = format.colorSpace;
    create.imageExtent = {width, height};
    create.imageArrayLayers = 1;
    create.imageUsage = VK_IMAGE_USAGE_TRANSFER_DST_BIT;
    create.imageSharingMode = VK_SHARING_MODE_EXCLUSIVE;
    create.preTransform = capabilities.currentTransform;
    for (auto alpha : {VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR, VK_COMPOSITE_ALPHA_INHERIT_BIT_KHR,
                       VK_COMPOSITE_ALPHA_PRE_MULTIPLIED_BIT_KHR, VK_COMPOSITE_ALPHA_POST_MULTIPLIED_BIT_KHR}) {
        if (capabilities.supportedCompositeAlpha & alpha) {
            create.compositeAlpha = alpha;
            break;
        }
    }
    create.presentMode = mode;
    create.clipped = VK_TRUE;
    create.oldSwapchain = swapchain;
    for (auto &frame : frames) waitForFrame(frame, "Waiting for Vulkan window resize");
    check(vkDeviceWaitIdle(device), "Retiring Vulkan swapchain");
    VkSwapchainKHR next = VK_NULL_HANDLE;
    check(vkCreateSwapchainKHR(device, &create, nullptr, &next), "Creating Vulkan swapchain");
    if (swapchain) vkDestroySwapchainKHR(device, swapchain, nullptr);
    swapchain = next;
    for (auto semaphore : presented) vkDestroySemaphore(device, semaphore, nullptr);
    presented.clear();
    check(vkGetSwapchainImagesKHR(device, swapchain, &count, nullptr), "Counting Vulkan backbuffers");
    swapImages.resize(count);
    check(vkGetSwapchainImagesKHR(device, swapchain, &count, swapImages.data()), "Reading Vulkan backbuffers");
    initializedImages.assign(count, false);
    VkSemaphoreCreateInfo semaphore{VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO};
    for (uint32_t index = 0; index < count; index++) {
        VkSemaphore value = VK_NULL_HANDLE;
        check(vkCreateSemaphore(device, &semaphore, nullptr, &value), "Creating Vulkan present semaphore");
        presented.push_back(value);
    }
    extent = {width, height};
    const char *modeName = mode == VK_PRESENT_MODE_MAILBOX_KHR ? "mailbox" : "fifo";
    std::fprintf(stderr, "meshnet: Vulkan %s presentation, %zu swapchain images, %u frame slots\n",
        modeName, swapImages.size(), framesInFlight);
    vsync = synchronize;
    recreateSwapchain = false;
    screen = image(width, height, 1, false);
    screenDepth = image(width, height, 1, true);
    screen->inverted = true;
    screenDepth->inverted = true;
}

uint32_t Renderer::memoryType(uint32_t bits, VkMemoryPropertyFlags flags) const {
    for (uint32_t index = 0; index < memory.memoryTypeCount; index++) {
        if ((bits & (1u << index)) && (memory.memoryTypes[index].propertyFlags & flags) == flags) return index;
    }
    throw std::runtime_error("No compatible Vulkan memory type");
}

std::shared_ptr<Buffer> Renderer::buffer(VkDeviceSize size, VkBufferUsageFlags usage) {
    size = std::max<VkDeviceSize>((size + 3) & ~VkDeviceSize(3), 4);
    auto object = std::make_shared<Buffer>(device, size);
    VkBufferCreateInfo info{VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO};
    info.size = size;
    info.usage = usage;
    info.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
    check(vkCreateBuffer(device, &info, nullptr, &object->handle), "Creating Vulkan buffer");
    VkMemoryRequirements requirements{};
    vkGetBufferMemoryRequirements(device, object->handle, &requirements);
    VkMemoryAllocateInfo allocation{VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO};
    allocation.allocationSize = requirements.size;
    allocation.memoryTypeIndex = memoryType(requirements.memoryTypeBits, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
    check(vkAllocateMemory(device, &allocation, nullptr, &object->memory), "Allocating Vulkan buffer memory");
    check(vkBindBufferMemory(device, object->handle, object->memory, 0), "Binding Vulkan buffer memory");
    check(vkMapMemory(device, object->memory, 0, size, 0, reinterpret_cast<void **>(&object->data)), "Mapping Vulkan buffer");
    return object;
}

std::shared_ptr<Image> Renderer::image(uint32_t width, uint32_t height, uint32_t levels, bool depth) {
    auto object = std::make_shared<Image>(device, width, height, levels, depth);
    VkImageCreateInfo info{VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO};
    info.imageType = VK_IMAGE_TYPE_2D;
    info.format = depth ? depthFormat : colorFormat;
    info.extent = {width, height, 1};
    info.mipLevels = levels;
    info.arrayLayers = 1;
    info.samples = VK_SAMPLE_COUNT_1_BIT;
    info.tiling = VK_IMAGE_TILING_OPTIMAL;
    info.usage = VK_IMAGE_USAGE_SAMPLED_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT
        | (depth ? VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT : VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT);
    info.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
    check(vkCreateImage(device, &info, nullptr, &object->handle), "Creating Vulkan image");
    VkMemoryRequirements requirements{};
    vkGetImageMemoryRequirements(device, object->handle, &requirements);
    VkMemoryAllocateInfo allocation{VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO};
    allocation.allocationSize = requirements.size;
    allocation.memoryTypeIndex = memoryType(requirements.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
    check(vkAllocateMemory(device, &allocation, nullptr, &object->memory), "Allocating Vulkan image memory");
    check(vkBindImageMemory(device, object->handle, object->memory, 0), "Binding Vulkan image memory");
    VkImageViewCreateInfo view{VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO};
    view.image = object->handle;
    view.viewType = VK_IMAGE_VIEW_TYPE_2D;
    view.format = info.format;
    view.subresourceRange = {object->aspect, 0, 1, 0, 1};
    check(vkCreateImageView(device, &view, nullptr, &object->attachment), "Creating Vulkan attachment view");
    if (levels == 1) {
        object->sample = object->attachment;
    } else {
        view.subresourceRange.levelCount = levels;
        check(vkCreateImageView(device, &view, nullptr, &object->sample), "Creating Vulkan sampling view");
    }
    return object;
}

VkShaderModule Renderer::shader(ShaderBytes code) {
    VkShaderModuleCreateInfo create{VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO};
    create.codeSize = code.size;
    create.pCode = code.words;
    VkShaderModule module = VK_NULL_HANDLE;
    check(vkCreateShaderModule(device, &create, nullptr, &module), "Creating Vulkan shader module");
    return module;
}

VkShaderModule Renderer::shader(const uint8_t *bytes, size_t size) {
    if (!bytes || !size || size % 4) throw std::runtime_error("Invalid SPIR-V shader");
    std::vector<uint32_t> words(size / 4);
    std::memcpy(words.data(), bytes, size);
    return shader({words.data(), size});
}

Frame &Renderer::begin() {
    if (recording) return *recording;
    Frame &frame = frames[submission % framesInFlight];
    auto now = std::chrono::steady_clock::now();
    waitForFrame(frame, "Waiting for Vulkan frame fence");
    fenceMilliseconds = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - now).count();
    reclaimTerrain();
    check(vkResetCommandPool(device, frame.commands, 0), "Resetting Vulkan frame commands");
    for (size_t index = 0; index <= frame.descriptorIndex && index < frame.descriptors.size(); index++) {
        check(vkResetDescriptorPool(device, frame.descriptors[index], 0), "Resetting Vulkan frame descriptor pool");
    }
    frame.descriptorIndex = 0;
    frame.descriptorCount = 0;
    frame.buffers.clear();
    frame.images.clear();
    for (auto &page : frame.pages) page->used = 0;
    VkCommandBufferBeginInfo info{VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO};
    info.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    check(vkBeginCommandBuffer(frame.command, &info), "Beginning Vulkan frame");
    recording = &frame;
    boundPipeline = VK_NULL_HANDLE;
    return frame;
}

void Renderer::waitForFrame(Frame &frame, const char *operation) {
    if (!frame.pending) return;
    check(vkWaitForFences(device, 1, &frame.fence, VK_TRUE, fenceTimeout), operation);
    frame.pending = false;
}

bool Renderer::readyToClose() const {
    for (const auto &frame : frames) {
        if (!frame.pending) continue;
        auto result = vkWaitForFences(device, 1, &frame.fence, VK_TRUE, fenceTimeout);
        if (result != VK_SUCCESS && result != VK_ERROR_DEVICE_LOST) return false;
    }
    return true;
}

void Renderer::endRendering() {
    if (!activeColor) return;
    vkCmdEndRendering(recording->command);
    activeColor = activeDepth = VK_NULL_HANDLE;
}

void Renderer::submit(VkSemaphore wait, VkSemaphore signal, bool synchronous) {
    Frame &frame = begin();
    endRendering();
    check(vkEndCommandBuffer(frame.command), "Ending Vulkan frame");
    check(vkResetFences(device, 1, &frame.fence), "Resetting Vulkan frame fence");
    VkSubmitInfo info{VK_STRUCTURE_TYPE_SUBMIT_INFO};
    VkPipelineStageFlags stage = VK_PIPELINE_STAGE_ALL_COMMANDS_BIT;
    if (wait) {
        info.waitSemaphoreCount = 1;
        info.pWaitSemaphores = &wait;
        info.pWaitDstStageMask = &stage;
    }
    if (signal) {
        info.signalSemaphoreCount = 1;
        info.pSignalSemaphores = &signal;
    }
    info.commandBufferCount = 1;
    info.pCommandBuffers = &frame.command;
    check(vkQueueSubmit(queue, 1, &info, frame.fence), "Submitting Vulkan frame");
    frame.pending = true;
    recording = nullptr;
    submission++;
    if (synchronous) waitForFrame(frame, "Waiting for Vulkan readback");
}

Slice Renderer::stage(const void *bytes, VkDeviceSize size, VkDeviceSize alignment) {
    Frame &frame = begin();
    const VkDeviceSize padded = (size + 3) & ~VkDeviceSize(3);
    auto reserve = [&](const std::shared_ptr<Buffer> &page, VkDeviceSize offset) {
        page->used = offset + padded;
        auto destination = page->data + offset;
        if (bytes) std::memcpy(destination, bytes, size);
        if (padded > size) std::memset(destination + size, 0, padded - size);
        return Slice{page->handle, offset, destination};
    };
    for (const auto &page : frame.pages) {
        VkDeviceSize offset = (page->used + alignment - 1) & ~(alignment - 1);
        if (offset + padded <= page->size) return reserve(page, offset);
    }
    auto page = buffer(std::max(stageSize, padded), VK_BUFFER_USAGE_TRANSFER_SRC_BIT | VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT
        | VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_INDEX_BUFFER_BIT | VK_BUFFER_USAGE_VERTEX_BUFFER_BIT);
    frame.pages.push_back(page);
    return reserve(page, 0);
}

void Renderer::barrier(VkImage image, VkImageAspectFlags aspect, uint32_t levels, VkImageLayout before, VkImageLayout after) {
    VkImageMemoryBarrier transition{VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER};
    transition.srcAccessMask = before == VK_IMAGE_LAYOUT_UNDEFINED ? 0 : (VK_ACCESS_MEMORY_WRITE_BIT | VK_ACCESS_MEMORY_READ_BIT);
    transition.dstAccessMask = after == VK_IMAGE_LAYOUT_PRESENT_SRC_KHR ? 0 : (VK_ACCESS_MEMORY_WRITE_BIT | VK_ACCESS_MEMORY_READ_BIT);
    transition.oldLayout = before;
    transition.newLayout = after;
    transition.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    transition.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    transition.image = image;
    transition.subresourceRange = {aspect, 0, levels, 0, 1};
    vkCmdPipelineBarrier(begin().command, VK_PIPELINE_STAGE_ALL_COMMANDS_BIT, VK_PIPELINE_STAGE_ALL_COMMANDS_BIT, 0,
        0, nullptr, 0, nullptr, 1, &transition);
}

void Renderer::transition(Image &object, VkImageLayout layout) {
    if (object.layout == layout) return;
    endRendering();
    barrier(object.handle, object.aspect, object.levels, object.layout, layout);
    object.layout = layout;
}

std::shared_ptr<Image> Renderer::color(int target) {
    if (!target) return screen;
    auto found = targets.find(target);
    if (found == targets.end()) return {};
    auto texture = textures.find(found->second.color);
    return texture == textures.end() ? nullptr : texture->second.image;
}

std::shared_ptr<Image> Renderer::depth(int target) {
    if (!target) return screenDepth;
    auto found = targets.find(target);
    if (found == targets.end()) return {};
    auto texture = textures.find(found->second.depth);
    return texture == textures.end() ? nullptr : texture->second.image;
}

void Renderer::renderTo(const std::shared_ptr<Image> &destination, const std::shared_ptr<Image> &depth,
                        int clearMask, VkClearColorValue clearColor, float clearDepth) {
    if (activeColor == destination->handle && activeDepth == (depth ? depth->handle : VK_NULL_HANDLE)) return;
    endRendering();
    auto attach = [&](Image &image, VkImageLayout layout) {
        barrier(image.handle, image.aspect, image.levels, image.layout, layout);
        image.layout = layout;
    };
    attach(*destination, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL);
    if (depth) attach(*depth, VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL);
    Frame &frame = begin();
    frame.images.push_back(destination);
    if (depth) frame.images.push_back(depth);

    VkRenderingAttachmentInfo colorInfo{VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO};
    colorInfo.imageView = destination->attachment;
    colorInfo.imageLayout = destination->layout;
    colorInfo.loadOp = (clearMask & 16384) ? VK_ATTACHMENT_LOAD_OP_CLEAR : VK_ATTACHMENT_LOAD_OP_LOAD;
    colorInfo.storeOp = VK_ATTACHMENT_STORE_OP_STORE;
    colorInfo.clearValue.color = clearColor;
    VkRenderingAttachmentInfo depthInfo{VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO};
    depthInfo.imageView = depth ? depth->attachment : VK_NULL_HANDLE;
    depthInfo.imageLayout = VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;
    depthInfo.loadOp = (clearMask & 256) ? VK_ATTACHMENT_LOAD_OP_CLEAR : VK_ATTACHMENT_LOAD_OP_LOAD;
    depthInfo.storeOp = VK_ATTACHMENT_STORE_OP_STORE;
    depthInfo.clearValue.depthStencil = {clearDepth, 0};
    VkRenderingInfo info{VK_STRUCTURE_TYPE_RENDERING_INFO};
    info.renderArea.extent = {destination->width, destination->height};
    info.layerCount = 1;
    info.colorAttachmentCount = 1;
    info.pColorAttachments = &colorInfo;
    info.pDepthAttachment = depth ? &depthInfo : nullptr;
    vkCmdBeginRendering(frame.command, &info);
    activeColor = destination->handle;
    activeDepth = depth ? depth->handle : VK_NULL_HANDLE;
}

void Renderer::clear(int target, int mask, VkClearColorValue rgba, float value) {
    auto destination = color(target);
    auto depthImage = depth(target);
    if (!destination || !(mask & 16640)) return;
    if (activeColor != destination->handle || activeDepth != (depthImage ? depthImage->handle : VK_NULL_HANDLE)) {
        renderTo(destination, depthImage, mask, rgba, value);
        return;
    }
    std::array<VkClearAttachment, 2> attachments{};
    uint32_t count = 0;
    if (mask & 16384) {
        attachments[count].aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
        attachments[count++].clearValue.color = rgba;
    }
    if ((mask & 256) && depthImage) {
        attachments[count].aspectMask = VK_IMAGE_ASPECT_DEPTH_BIT;
        attachments[count++].clearValue.depthStencil = {value, 0};
    }
    VkClearRect rect{{{0, 0}, {destination->width, destination->height}}, 0, 1};
    if (count) vkCmdClearAttachments(recording->command, count, attachments.data(), 1, &rect);
}

VkSampler Renderer::sampler(const Texture &texture) {
    const Image &image = *texture.image;
    std::array<int, 6> key{texture.min, texture.mag, texture.wrapS, texture.wrapT, texture.maxLevel, static_cast<int>(image.levels)};
    auto previous = samplers.find(key);
    if (previous != samplers.end()) return previous->second;
    auto address = [](int mode) {
        if (mode == 10496 || mode == 33071) return VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
        if (mode == 33648) return VK_SAMPLER_ADDRESS_MODE_MIRRORED_REPEAT;
        return VK_SAMPLER_ADDRESS_MODE_REPEAT;
    };
    VkSamplerCreateInfo create{VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO};
    create.magFilter = texture.mag == 9729 ? VK_FILTER_LINEAR : VK_FILTER_NEAREST;
    create.minFilter = texture.min == 9729 || texture.min == 9985 || texture.min == 9987 ? VK_FILTER_LINEAR : VK_FILTER_NEAREST;
    create.mipmapMode = texture.min == 9986 || texture.min == 9987 ? VK_SAMPLER_MIPMAP_MODE_LINEAR : VK_SAMPLER_MIPMAP_MODE_NEAREST;
    create.addressModeU = address(texture.wrapS);
    create.addressModeV = address(texture.wrapT);
    create.addressModeW = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    create.maxLod = texture.min >= 9984 ? std::clamp(texture.maxLevel, 0, static_cast<int>(image.levels) - 1) : 0;
    VkSampler object = VK_NULL_HANDLE;
    check(vkCreateSampler(device, &create, nullptr, &object), "Creating Vulkan sampler");
    samplers.emplace(key, object);
    return object;
}

VkBlendFactor blendFactor(int value) {
    if (value == 0) return VK_BLEND_FACTOR_ZERO;
    if (value == 1) return VK_BLEND_FACTOR_ONE;
    constexpr VkBlendFactor factors[] = {VK_BLEND_FACTOR_SRC_COLOR, VK_BLEND_FACTOR_ONE_MINUS_SRC_COLOR,
        VK_BLEND_FACTOR_SRC_ALPHA, VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA, VK_BLEND_FACTOR_DST_ALPHA,
        VK_BLEND_FACTOR_ONE_MINUS_DST_ALPHA, VK_BLEND_FACTOR_DST_COLOR, VK_BLEND_FACTOR_ONE_MINUS_DST_COLOR,
        VK_BLEND_FACTOR_SRC_ALPHA_SATURATE};
    if (value >= 768 && value <= 776) return factors[value - 768];
    if (value >= 32769 && value <= 32772) return static_cast<VkBlendFactor>(VK_BLEND_FACTOR_CONSTANT_COLOR + value - 32769);
    return VK_BLEND_FACTOR_ONE;
}

VkBlendOp blendEquation(int value) {
    switch (value) {
        case 32775: return VK_BLEND_OP_MIN;
        case 32776: return VK_BLEND_OP_MAX;
        case 32778: return VK_BLEND_OP_SUBTRACT;
        case 32779: return VK_BLEND_OP_REVERSE_SUBTRACT;
        default: return VK_BLEND_OP_ADD;
    }
}

VkPipeline Renderer::pipeline(const DrawState &state, VkPrimitiveTopology topology, bool depth, uint32_t textureFlags,
                              bool chunk) {
    const int *p = state.pipeline;
    auto effect = effects.find(p[26]);
    bool post = effect != effects.end();
    uint32_t stride = static_cast<uint32_t>(p[24]);
    int logic = logicOps && p[27] >= 5376 && p[27] <= 5391 ? p[27] : 0;
    int flags = textureFlags | (reinterpret_cast<const uint32_t *>(state.bytes)[117] ? 8u : 0u)
        | (reinterpret_cast<const uint32_t *>(state.bytes)[118] ? 16u : 0u);
    PipelineKey key{static_cast<int>(topology), depth, p[1], p[2], p[3], p[4], p[5], p[6],
        p[7], p[8], p[9], p[10], p[11], p[26], logic, post ? static_cast<int>(stride) : flags, chunk};
    auto cached = pipelines.find(key);
    if (cached != pipelines.end()) return cached->second;

    VkSpecializationMapEntry constant{0, 0, sizeof(flags)};
    VkSpecializationInfo specialization{1, &constant, sizeof(flags), &flags};
    VkPipelineShaderStageCreateInfo stages[2] = {
        {VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, nullptr, 0, VK_SHADER_STAGE_VERTEX_BIT,
            post ? effect->second.vertex : chunk ? chunkVertex : vertex, "main", nullptr},
        {VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, nullptr, 0, VK_SHADER_STAGE_FRAGMENT_BIT,
            post ? effect->second.fragment : chunk ? chunkFragment : fragment, "main", post ? nullptr : &specialization}
    };
    VkPipelineVertexInputStateCreateInfo input{VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO};
    VkVertexInputBindingDescription binding{0, stride, VK_VERTEX_INPUT_RATE_VERTEX};
    VkVertexInputAttributeDescription position{0, 0, VK_FORMAT_R32G32B32_SFLOAT, 0};
    if (post) {
        input.vertexBindingDescriptionCount = 1;
        input.pVertexBindingDescriptions = &binding;
        input.vertexAttributeDescriptionCount = 1;
        input.pVertexAttributeDescriptions = &position;
    }
    VkPipelineInputAssemblyStateCreateInfo assembly{VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO};
    assembly.topology = topology;
    VkPipelineViewportStateCreateInfo viewport{VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO};
    viewport.viewportCount = viewport.scissorCount = 1;
    VkPipelineRasterizationStateCreateInfo rasterizer{VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO};
    rasterizer.polygonMode = VK_POLYGON_MODE_FILL;
    rasterizer.cullMode = p[10] ? VK_CULL_MODE_BACK_BIT : VK_CULL_MODE_NONE;
    rasterizer.frontFace = VK_FRONT_FACE_COUNTER_CLOCKWISE;
    rasterizer.lineWidth = 1.0f;
    rasterizer.depthBiasEnable = VK_TRUE;
    VkPipelineMultisampleStateCreateInfo samples{VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO};
    samples.rasterizationSamples = VK_SAMPLE_COUNT_1_BIT;
    VkPipelineDepthStencilStateCreateInfo depthInfo{VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO};
    depthInfo.depthTestEnable = depth && p[7];
    depthInfo.depthWriteEnable = depth && p[7] && p[9];
    depthInfo.depthCompareOp = static_cast<VkCompareOp>(std::clamp(p[8] - 512, 0, 7));
    VkPipelineColorBlendAttachmentState attachment{};
    attachment.blendEnable = p[1] && !logic;
    attachment.srcColorBlendFactor = blendFactor(p[2]);
    attachment.dstColorBlendFactor = blendFactor(p[3]);
    attachment.srcAlphaBlendFactor = blendFactor(p[4]);
    attachment.dstAlphaBlendFactor = blendFactor(p[5]);
    attachment.colorBlendOp = attachment.alphaBlendOp = blendEquation(p[6]);
    attachment.colorWriteMask = p[11] & 15;
    VkPipelineColorBlendStateCreateInfo blend{VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO};
    blend.logicOpEnable = logic != 0;
    blend.logicOp = logic ? static_cast<VkLogicOp>(logic - 5376) : VK_LOGIC_OP_COPY;
    blend.attachmentCount = 1;
    blend.pAttachments = &attachment;
    const VkDynamicState values[] = {VK_DYNAMIC_STATE_VIEWPORT, VK_DYNAMIC_STATE_SCISSOR, VK_DYNAMIC_STATE_DEPTH_BIAS};
    VkPipelineDynamicStateCreateInfo dynamic{VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO};
    dynamic.dynamicStateCount = 3;
    dynamic.pDynamicStates = values;
    VkPipelineRenderingCreateInfo rendering{VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO};
    rendering.colorAttachmentCount = 1;
    rendering.pColorAttachmentFormats = &colorFormat;
    rendering.depthAttachmentFormat = depth ? depthFormat : VK_FORMAT_UNDEFINED;
    VkGraphicsPipelineCreateInfo create{VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO};
    create.pNext = &rendering;
    create.stageCount = 2;
    create.pStages = stages;
    create.pVertexInputState = &input;
    create.pInputAssemblyState = &assembly;
    create.pViewportState = &viewport;
    create.pRasterizationState = &rasterizer;
    create.pMultisampleState = &samples;
    create.pDepthStencilState = &depthInfo;
    create.pColorBlendState = &blend;
    create.pDynamicState = &dynamic;
    create.layout = pipelineLayout;
    VkPipeline object = VK_NULL_HANDLE;
    check(vkCreateGraphicsPipelines(device, pipelineCache, 1, &create, nullptr, &object), "Creating Vulkan draw pipeline");
    pipelines.emplace(key, object);
    return object;
}

VkDescriptorSet Renderer::descriptor(Slice uniforms, Slice vertices, VkDeviceSize uniformSize,
    VkDeviceSize vertexSize, const std::array<Texture *, maxTextures> &sampled, const Slice *units, VkDeviceSize unitSize) {
    Frame &frame = begin();
    constexpr uint32_t sets = 2048;
    if (frame.descriptorCount == sets) {
        frame.descriptorIndex++;
        frame.descriptorCount = 0;
    }
    VkDescriptorSet result = VK_NULL_HANDLE;
    while (true) {
        if (frame.descriptorIndex == frame.descriptors.size()) {
            const VkDescriptorPoolSize sizes[] = {{VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, sets},
                {VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, sets * 2}, {VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, sets * maxTextures}};
            VkDescriptorPoolCreateInfo create{VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO};
            create.maxSets = sets;
            create.poolSizeCount = 3;
            create.pPoolSizes = sizes;
            VkDescriptorPool pool = VK_NULL_HANDLE;
            check(vkCreateDescriptorPool(device, &create, nullptr, &pool), "Creating Vulkan descriptor pool");
            frame.descriptors.push_back(pool);
        }
        VkDescriptorSetAllocateInfo allocation{VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO};
        allocation.descriptorPool = frame.descriptors[frame.descriptorIndex];
        allocation.descriptorSetCount = 1;
        allocation.pSetLayouts = &descriptorLayout;
        VkResult status = vkAllocateDescriptorSets(device, &allocation, &result);
        if (status == VK_SUCCESS) break;
        if (status != VK_ERROR_OUT_OF_POOL_MEMORY && status != VK_ERROR_FRAGMENTED_POOL) {
            check(status, "Allocating Vulkan draw descriptor");
        }
        frame.descriptorIndex++;
        frame.descriptorCount = 0;
    }
    frame.descriptorCount++;

    const VkDescriptorBufferInfo buffers[] = {{uniforms.buffer, uniforms.offset, uniformSize},
        {vertices.buffer, vertices.offset, vertexSize}};
    std::array<VkDescriptorImageInfo, maxTextures> images{};
    std::array<VkWriteDescriptorSet, maxTextures + 3> writes{};
    writes[0] = {VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, nullptr, result, 0, 0, 1,
        VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, nullptr, buffers, nullptr};
    writes[1] = {VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, nullptr, result, 1, 0, 1,
        VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, nullptr, buffers + 1, nullptr};
    for (uint32_t index = 0; index < maxTextures; index++) {
        Texture &texture = *sampled[index];
        images[index] = {sampler(texture), texture.image->sample, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL};
        writes[index + 2] = {VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, nullptr, result, index + 2, 0, 1,
            VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, &images[index], nullptr, nullptr};
    }
    VkDescriptorBufferInfo unitBuffer{};
    if (units) {
        unitBuffer = {units->buffer, units->offset, unitSize};
        writes[unitsBinding] = {VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, nullptr, result, unitsBinding, 0, 1,
            VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, nullptr, &unitBuffer, nullptr};
    }
    vkUpdateDescriptorSets(device, writes.size() - (units ? 0 : 1), writes.data(), 0, nullptr);
    return result;
}

void Renderer::indices(uint32_t quads) {
    if (quads <= quadCapacity) return;
    quadCapacity = std::max(quads, std::max(quadCapacity * 2, 256u));
    quadIndices = buffer(uint64_t(quadCapacity) * 6 * sizeof(uint32_t), VK_BUFFER_USAGE_INDEX_BUFFER_BIT);
    auto output = reinterpret_cast<uint32_t *>(quadIndices->data);
    for (uint32_t index = 0; index < quadCapacity; index++) {
        uint32_t base = index * 4;
        std::array<uint32_t, 6> quad{base, base + 1, base + 2, base + 2, base + 3, base};
        std::copy(quad.begin(), quad.end(), output + index * 6);
    }
}

VkPrimitiveTopology primitive(int mode) {
    switch (mode) {
        case 0: return VK_PRIMITIVE_TOPOLOGY_POINT_LIST;
        case 1: return VK_PRIMITIVE_TOPOLOGY_LINE_LIST;
        case 2:
        case 3: return VK_PRIMITIVE_TOPOLOGY_LINE_STRIP;
        case 5: return VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP;
        default: return VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
    }
}

DrawBindings Renderer::bindDraw(const DrawState &state, int mode, const std::shared_ptr<Image> &destination, bool chunk) {
    const int *p = state.pipeline;
    Frame &frame = begin();
    auto depthImage = depth(p[0]);
    alignas(16) std::array<uint8_t, stateSize> uniforms{};
    std::memcpy(uniforms.data(), state.bytes, uniforms.size());
    auto *flags = reinterpret_cast<uint32_t *>(uniforms.data() + 464);
    auto effect = effects.find(p[26]);
    bool post = effect != effects.end();
    if (p[26] && !post) throw std::runtime_error("Unknown Vulkan post effect");
    std::array<Texture *, maxTextures> sampled{};
    for (uint32_t index = 0; index < maxTextures; index++) {
        int unit = post ? (index < effect->second.units.size() ? effect->second.units[index] : -1)
                        : (index < 3 && (flags[0] & (1u << index)) ? index : -1);
        auto found = unit >= 0 && unit < 16 ? textures.find(state.textures[unit]) : textures.end();
        auto texture = found == textures.end() || !found->second.image ? &white : &found->second;
        if (texture->image == destination || texture->image == depthImage) texture = &white;
        sampled[index] = texture;
        transition(*texture->image, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);
        if (texture != &white) frame.images.push_back(texture->image);
        if (!post && index < 3 && texture->image->inverted) flags[3] |= 256u << index;
    }
    const void *uniformData = post ? effect->second.uniforms.data() : uniforms.data();
    VkDeviceSize uniformSize = post ? effect->second.uniforms.size() : uniforms.size();
    if (!uniformSize) throw std::runtime_error("Vulkan post effect has no uniform data");
    Slice uniform = stage(uniformData, uniformSize, properties.limits.minUniformBufferOffsetAlignment);

    renderTo(destination, depthImage);
    auto command = frame.command;
    VkPipeline drawPipeline = pipeline(state, primitive(mode), depthImage != nullptr, flags[0] & 7u, chunk);
    if (boundPipeline != drawPipeline) {
        vkCmdBindPipeline(command, VK_PIPELINE_BIND_POINT_GRAPHICS, drawPipeline);
        boundPipeline = drawPipeline;
    }
    VkViewport viewport{static_cast<float>(p[20]), static_cast<float>(p[21]), static_cast<float>(std::max(1, p[22])),
        static_cast<float>(std::max(1, p[23])), 0.0f, 1.0f};
    VkRect2D scissor{{0, 0}, {destination->width, destination->height}};
    vkCmdSetViewport(command, 0, 1, &viewport);
    vkCmdSetScissor(command, 0, 1, &scissor);
    float slope, constant;
    std::memcpy(&slope, p + 13, 4);
    std::memcpy(&constant, p + 14, 4);
    vkCmdSetDepthBias(command, p[12] ? constant : 0.0f, 0.0f, p[12] ? slope : 0.0f);
    return {uniform, uniformSize, sampled};
}
void Renderer::draw(const void *source, int first, int count, int mode, int mesh, const DrawState &state,
                    const Geometry &position) {
    if (first < 0 || count <= 0 || state.pipeline[24] <= 0) return;
    const int *p = state.pipeline;
    auto destination = color(p[0]);
    if (!destination) return;
    Frame &frame = begin();
    VkDeviceSize size = (uint64_t(first) + count) * p[24];
    Slice vertices{};
    uint32_t baseVertex = 0;
    if (source) {
        vertices = stage(source, size, properties.limits.minStorageBufferOffsetAlignment);
        size = (size + 3) & ~VkDeviceSize(3);
    } else {
        auto found = meshes.find(mesh);
        if (found == meshes.end()) return;
        const auto &object = found->second;
        if (object.range.page) {
            if (size > object.range.length || p[24] != 32) return;
            const auto &page = object.range.page->buffer;
            vertices = {page->handle, 0, page->data};
            size = page->size;
            baseVertex = object.range.offset / p[24];
        } else {
            if (!object.buffer || size > object.buffer->used) return;
            frame.buffers.push_back(object.buffer);
            vertices = {object.buffer->handle, 0, object.buffer->data};
            size = object.buffer->size;
        }
    }
    auto bindings = bindDraw(state, mode, destination);
    auto command = frame.command;
    VkDescriptorSet set = descriptor(bindings.uniform, vertices, bindings.uniformSize, size, bindings.sampled);
    vkCmdBindDescriptorSets(command, VK_PIPELINE_BIND_POINT_GRAPHICS, pipelineLayout, 0, 1, &set, 0, nullptr);
    Geometry geometry = position;
    geometry.stride = p[24];
    if (p[26]) {
        vkCmdBindVertexBuffers(command, 0, 1, &vertices.buffer, &vertices.offset);
    } else {
        vkCmdPushConstants(command, pipelineLayout, VK_SHADER_STAGE_VERTEX_BIT, 0, sizeof(geometry), &geometry);
    }
    if (mode == 7) {
        indices((first + count + 3) / 4);
        frame.buffers.push_back(quadIndices);
        vkCmdBindIndexBuffer(command, quadIndices->handle, 0, VK_INDEX_TYPE_UINT32);
        vkCmdDrawIndexed(command, (count / 4) * 6, 1, (first / 4) * 6, baseVertex, 0);
    } else if (mode == 2 || mode == 6) {
        uint32_t indexCount = mode == 2 ? count + 1 : (std::max(0, count - 2) * 3);
        if (!indexCount) return;
        Slice scratch = stage(nullptr, uint64_t(indexCount) * sizeof(uint32_t));
        auto output = reinterpret_cast<uint32_t *>(scratch.data);
        if (mode == 2) {
            for (int vertex = 0; vertex < count; vertex++) output[vertex] = first + vertex;
            output[count] = first;
        } else {
            for (int triangle = 0; triangle < count - 2; triangle++) {
                output[triangle * 3] = first;
                output[triangle * 3 + 1] = first + triangle + 1;
                output[triangle * 3 + 2] = first + triangle + 2;
            }
        }
        vkCmdBindIndexBuffer(command, scratch.buffer, scratch.offset, VK_INDEX_TYPE_UINT32);
        vkCmdDrawIndexed(command, indexCount, 1, 0, baseVertex, 0);
    } else {
        vkCmdDraw(command, count, 1, first + baseVertex, 0);
    }
}

TerrainRange Renderer::storeTerrain(const void *source, VkDeviceSize size, bool translucent) {
    constexpr VkDeviceSize alignment = 256;
    VkDeviceSize reserved = (size + alignment - 1) & ~(alignment - 1);
    auto reserve = [&](TerrainPage &page, std::map<VkDeviceSize, VkDeviceSize>::iterator region) {
        auto [offset, capacity] = *region;
        page.available.erase(region);
        if (capacity > reserved) page.available.emplace(offset + reserved, capacity - reserved);
        if (capacity == page.largestRange) {
            page.largestRange = 0;
            for (const auto &entry : page.available) page.largestRange = std::max(page.largestRange, entry.second);
        }
        std::memcpy(page.buffer->data + offset, source, size);
        return TerrainRange{&page, offset, size, reserved};
    };
    for (auto &page : terrainPages) {
        if (page->translucent != translucent || page->largestRange < reserved) continue;
        auto fit = std::find_if(page->available.begin(), page->available.end(),
            [reserved](const auto &entry) { return entry.second >= reserved; });
        if (fit != page->available.end()) return reserve(*page, fit);
    }
    auto page = std::make_unique<TerrainPage>();
    VkDeviceSize targetSize = (translucent ? 64u : 32u) * 1024 * 1024;
    page->translucent = translucent;
    page->buffer = buffer(std::max(reserved, std::min<VkDeviceSize>(targetSize, properties.limits.maxStorageBufferRange)),
        VK_BUFFER_USAGE_STORAGE_BUFFER_BIT);
    page->largestRange = page->buffer->size;
    page->available.emplace(0, page->buffer->size);
    terrainPages.push_back(std::move(page));
    return reserve(*terrainPages.back(), terrainPages.back()->available.begin());
}
void Renderer::retireTerrain(TerrainRange &range) {
    if (!range.page) return;
    retiredTerrain.push_back({range, submission + framesInFlight});
    range = {};
}
void Renderer::retireTerrain(Mesh &mesh) {
    retireTerrain(mesh.range);
}
void Renderer::reclaimTerrain() {
    while (!retiredTerrain.empty() && retiredTerrain.front().submission <= submission) {
        auto range = retiredTerrain.front().range;
        retiredTerrain.pop_front();
        auto &available = range.page->available;
        auto next = available.lower_bound(range.offset);
        if (next != available.begin()) {
            auto previous = std::prev(next);
            if (previous->first + previous->second == range.offset) {
                range.offset = previous->first;
                range.reserved += previous->second;
                available.erase(previous);
            }
        }
        if (next != available.end() && range.offset + range.reserved == next->first) {
            range.reserved += next->second;
            next = available.erase(next);
        }
        available.emplace_hint(next, range.offset, range.reserved);
        range.page->largestRange = std::max(range.page->largestRange, range.reserved);
    }
}
void Renderer::commitTerrain(Mesh &mesh, const void *source, VkDeviceSize sourceSize, const terrainmesh::Result &geometry) {
    if (geometry.vertices) {
        auto range = storeTerrain(source, geometry.vertices * terrainmesh::stride, mesh.layer >= 3);
        retireTerrain(mesh);
        mesh.range = range;
    } else {
        retireTerrain(mesh);
    }
    mesh.geometry = geometry;
    sourceTerrainVertices += sourceSize / terrainmesh::stride;
    savedTerrainVertices += geometry.saved;
}
void Renderer::uploadTerrain(Mesh &mesh, const void *source, VkDeviceSize size) {
    if (size % sizeof(terrainmesh::Quad)) throw std::runtime_error("Vulkan terrain contains a partial quad");
    static thread_local terrainmesh::Builder terrainBuilder;
    auto geometry = terrainBuilder.build(source, size, greedyTerrain && mesh.layer < 3, mesh.layer < 3);
    commitTerrain(mesh, terrainBuilder.output.data(), size, geometry);
}
void Renderer::submitUnits(TerrainPage &page, const std::vector<ChunkUnit> &units, uint32_t width, const DrawBindings &bindings) {
    if (units.empty()) return;
    VkDeviceSize size = units.size() * sizeof(ChunkUnit);
    Slice unitData = stage(units.data(), size, properties.limits.minStorageBufferOffsetAlignment);
    Slice vertices{page.buffer->handle, 0, page.buffer->data};
    VkDescriptorSet set = descriptor(bindings.uniform, vertices, bindings.uniformSize,
        page.buffer->size, bindings.sampled, &unitData, size);
    auto command = recording->command;
    vkCmdBindDescriptorSets(command, VK_PIPELINE_BIND_POINT_GRAPHICS, pipelineLayout, 0, 1, &set, 0, nullptr);
    vkCmdDrawIndexed(command, width * 6 / 4, units.size(), 0, 0, 0);
    terrainCommands++;
}
void Renderer::distant(const DrawState &state, const int32_t *columns, int count, double x, double y, double z) {
    auto destination = color(state.pipeline[0]);
    if (!destination) return;
    for (auto &entry : distantUnits) entry.second.clear();
    auto *matrix = reinterpret_cast<const float *>(state.bytes);
    std::array<std::array<float, 4>, 6> planes{};
    for (int axis = 0; axis < 3; axis++) {
        for (int column = 0; column < 4; column++) {
            planes[axis * 2][column] = matrix[column * 4 + 3] + matrix[column * 4 + axis];
            planes[axis * 2 + 1][column] = matrix[column * 4 + 3] - matrix[column * 4 + axis];
        }
    }
    bool found = false;
    for (int index = 0; index < count; index++) {
        auto entry = distantMeshes.find(columns[index]);
        if (entry == distantMeshes.end()) continue;
        const auto &mesh = entry->second;
        float dx = mesh.x - x, dy = -y, dz = mesh.z - z;
        bool visible = std::all_of(planes.begin(), planes.end(), [&](const auto &plane) {
            return plane[0] * (dx + (plane[0] >= 0 ? 16 : 0))
                + plane[1] * (dy + (plane[1] >= 0 ? mesh.maxY : mesh.minY))
                + plane[2] * (dz + (plane[2] >= 0 ? 16 : 0)) + plane[3] >= 0;
        });
        if (!visible) continue;
        uint32_t start = mesh.range.offset / terrainmesh::stride;
        uint32_t vertices = mesh.range.length / terrainmesh::stride;
        uint32_t width = chunkUnitWidths.back();
        auto &units = distantUnits[mesh.range.page];
        for (uint32_t offset = 0; offset < vertices; offset += width) {
            units.push_back({{dx, dy, dz}, start + offset, std::min(width, vertices - offset)});
        }
        found = true;
    }
    if (!found) return;
    auto bindings = bindDraw(state, 7, destination, true);
    auto &frame = *recording;
    indices(chunkUnitWidths.back() / 4);
    frame.buffers.push_back(quadIndices);
    vkCmdBindIndexBuffer(frame.command, quadIndices->handle, 0, VK_INDEX_TYPE_UINT32);
    for (auto &[page, units] : distantUnits) submitUnits(*page, units, chunkUnitWidths.back(), bindings);
}
void Renderer::terrain(int layer, const DrawState &state, double x, double y, double z, int distance) {
    if (layer < 0 || layer >= static_cast<int>(visibility.size())) return;
    if (state.pipeline[24] != terrainmesh::stride) throw std::runtime_error("Unexpected Vulkan terrain vertex stride");
    auto destination = color(state.pipeline[0]);
    if (!destination) return;
    auto translation = [&](const Mesh &mesh) {
        return std::array<float, 3>{static_cast<float>(mesh.origin[0] - x), static_cast<float>(mesh.origin[1] - y),
                                    static_cast<float>(mesh.origin[2] - z)};
    };
    if (layer == 3) {
        if (visibility[layer].empty()) return;
        auto bindings = bindDraw(state, 7, destination, true);
        auto &frame = *recording;
        indices(chunkUnitWidths.back() / 4);
        frame.buffers.push_back(quadIndices);
        vkCmdBindIndexBuffer(frame.command, quadIndices->handle, 0, VK_INDEX_TYPE_UINT32);
        TerrainPage *lastPage = nullptr;
        sortedTerrain.clear();
        for (auto id = visibility[layer].rbegin(); id != visibility[layer].rend(); ++id) {
            auto found = meshes.find(*id);
            if (found == meshes.end() || !found->second.range.page) continue;
            const Mesh &mesh = found->second;
            if (mesh.range.page != lastPage && lastPage) {
                submitUnits(*lastPage, sortedTerrain, chunkUnitWidths.back(), bindings);
                sortedTerrain.clear();
            }
            lastPage = mesh.range.page;
            auto offset = translation(mesh);
            uint32_t start = mesh.range.offset / terrainmesh::stride;
            uint32_t count = mesh.geometry.vertices;
            for (uint32_t first = 0; first < count; first += chunkUnitWidths.back()) {
                sortedTerrain.push_back({offset, start + first, std::min(chunkUnitWidths.back(), count - first)});
            }
            terrainCount++;
        }
        if (lastPage) submitUnits(*lastPage, sortedTerrain, chunkUnitWidths.back(), bindings);
        return;
    }
    for (auto &entry : visibleTerrain) for (auto &bucket : entry.second) bucket.clear();
    const double limit = distance * 16.0 + 32;
    bool anyVisible = false;
    bool cull = state.pipeline[10];
    for (int id : visibility[layer]) {
        auto found = meshes.find(id);
        if (found == meshes.end() || !found->second.range.page) continue;
        const Mesh &mesh = found->second;
        if (std::abs(mesh.origin[0] - x) > limit || std::abs(mesh.origin[2] - z) > limit) continue;
        auto offset = translation(mesh);
        auto &buckets = visibleTerrain[mesh.range.page];
        uint32_t base = mesh.range.offset / terrainmesh::stride;
        for (int face = 0; face < terrainmesh::faceCount; face++) {
            const auto &group = mesh.geometry.groups[face];
            if (!group.count) continue;
            if (cull && face < 6) {
                float camera = -offset[face / 2];
                if (face & 1 ? camera < group.minPlane - 0.015625f : camera > group.maxPlane + 0.015625f) continue;
            }
            for (uint32_t processed = 0; processed < group.count;) {
                uint32_t remaining = group.count - processed;
                size_t bucket = remaining <= chunkUnitWidths[0] ? 0 : remaining <= chunkUnitWidths[1] ? 1 : 2;
                uint32_t count = std::min(remaining, chunkUnitWidths[bucket]);
                buckets[bucket].push_back({offset, base + group.first + processed, count});
                processed += count;
            }
            anyVisible = true;
        }
        terrainCount++;
    }
    if (!anyVisible) return;
    auto bindings = bindDraw(state, 7, destination, true);
    auto &frame = *recording;
    indices(chunkUnitWidths.back() / 4);
    frame.buffers.push_back(quadIndices);
    vkCmdBindIndexBuffer(frame.command, quadIndices->handle, 0, VK_INDEX_TYPE_UINT32);
    for (auto &[page, buckets] : visibleTerrain) {
        for (size_t index = 0; index < buckets.size(); index++) submitUnits(*page, buckets[index], chunkUnitWidths[index], bindings);
    }
}
void Renderer::upload(Image &image, uint32_t level, int x, int y, int width, int height,
                      int rowBytes, int format, const uint8_t *source) {
    if (!source || width <= 0 || height <= 0) return;
    if (level >= image.levels || x < 0 || y < 0 || uint64_t(x) + width > mipSize(image.width, level)
        || uint64_t(y) + height > mipSize(image.height, level)) {
        throw std::runtime_error("Vulkan texture upload exceeds its allocation");
    }
    if (image.aspect != VK_IMAGE_ASPECT_COLOR_BIT) throw std::runtime_error("Cannot upload a color image to a depth texture");
    endRendering();
    Frame &frame = begin();
    Slice staging = stage(nullptr, uint64_t(width) * height * 4);
    int channels = format == 6408 || format == 32993 ? 4 : format == 6407 ? 3 : format == 33319 || format == 6410 ? 2 : 1;
    for (int row = 0; row < height; row++) {
        auto *target = staging.data + size_t(row) * width * 4;
        auto *input = source + size_t(row) * rowBytes;
        if (format == 6408) {
            std::memcpy(target, input, size_t(width) * 4);
            continue;
        }
        for (int column = 0; column < width; column++) {
            const auto *p = input + size_t(column) * channels;
            auto *q = target + size_t(column) * 4;
            if (format == 32993 || format == 6407) {
                q[0] = p[format == 32993 ? 2 : 0];
                q[1] = p[1];
                q[2] = p[format == 32993 ? 0 : 2];
                q[3] = channels == 4 ? p[3] : 255;
            } else {
                q[0] = q[1] = q[2] = format == 6406 ? 255 : p[0];
                q[3] = format == 6406 ? p[0] : channels == 2 ? p[1] : 255;
            }
        }
    }
    if (image.layout == VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL) {
        VkImageMemoryBarrier overwrite{VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER};
        overwrite.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
        overwrite.dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
        overwrite.oldLayout = overwrite.newLayout = image.layout;
        overwrite.srcQueueFamilyIndex = overwrite.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
        overwrite.image = image.handle;
        overwrite.subresourceRange = {image.aspect, level, 1, 0, 1};
        vkCmdPipelineBarrier(frame.command, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0,
            0, nullptr, 0, nullptr, 1, &overwrite);
    } else {
        transition(image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);
    }
    VkBufferImageCopy copy{};
    copy.bufferOffset = staging.offset;
    copy.imageSubresource = {image.aspect, level, 0, 1};
    copy.imageOffset = {x, y, 0};
    copy.imageExtent = {static_cast<uint32_t>(width), static_cast<uint32_t>(height), 1};
    vkCmdCopyBufferToImage(frame.command, staging.buffer, image.handle, image.layout, 1, &copy);
}

void Renderer::copyDepth(int source, int destination) {
    auto from = depth(source);
    auto to = depth(destination);
    if (!from || !to || from == to) return;
    Frame &frame = begin();
    frame.images.push_back(from);
    frame.images.push_back(to);
    endRendering();
    transition(*from, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL);
    transition(*to, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);
    VkImageCopy copy{};
    copy.srcSubresource = copy.dstSubresource = {VK_IMAGE_ASPECT_DEPTH_BIT, 0, 0, 1};
    copy.extent = {std::min(from->width, to->width), std::min(from->height, to->height), 1};
    vkCmdCopyImage(frame.command, from->handle, from->layout, to->handle, to->layout, 1, &copy);
}

void Renderer::download(Image &image, int level, int x, int y, int width, int height, int format, int type,
                        uint8_t *output) {
    if (!output || width <= 0 || height <= 0) return;
    if (level < 0 || static_cast<uint32_t>(level) >= image.levels || x < 0 || y < 0
        || uint64_t(x) + width > mipSize(image.width, level) || uint64_t(y) + height > mipSize(image.height, level)) {
        throw std::runtime_error("Vulkan readback exceeds the image allocation");
    }
    int channels = format == 6408 || format == 32993 ? 4 : format == 6407 ? 3 : format == 33319 || format == 6410 ? 2 : 1;
    if (type != 5121 && type != 5126) throw std::runtime_error("Unsupported Vulkan readback type");
    auto result = buffer(uint64_t(width) * height * 4, VK_BUFFER_USAGE_TRANSFER_DST_BIT);
    endRendering();
    transition(image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL);
    VkBufferImageCopy copy{};
    copy.imageSubresource = {image.aspect, static_cast<uint32_t>(level), 0, 1};
    copy.imageOffset = {x, image.inverted ? static_cast<int>(mipSize(image.height, level)) - y - height : y, 0};
    copy.imageExtent = {static_cast<uint32_t>(width), static_cast<uint32_t>(height), 1};
    auto &frame = begin();
    frame.buffers.push_back(result);
    vkCmdCopyImageToBuffer(frame.command, image.handle, image.layout, result->handle, 1, &copy);
    submit(VK_NULL_HANDLE, VK_NULL_HANDLE, true);
    for (int row = 0; row < height; row++) {
        const auto *input = result->data + size_t(image.inverted ? height - row - 1 : row) * width * 4;
        if (format == 6408 && type == 5121 && image.aspect == VK_IMAGE_ASPECT_COLOR_BIT) {
            std::memcpy(output + size_t(row) * width * 4, input, size_t(width) * 4);
            continue;
        }
        for (int column = 0; column < width; column++) {
            const auto *pixel = input + size_t(column) * 4;
            float rgba[4] = {0, 0, 0, 1};
            if (image.aspect == VK_IMAGE_ASPECT_DEPTH_BIT) {
                std::memcpy(rgba, pixel, 4);
            } else {
                for (int index = 0; index < 4; index++) rgba[index] = pixel[index] / 255.0f;
            }
            for (int channel = 0; channel < channels; channel++) {
                int component = format == 6406 || (format == 6410 && channel == 1) ? 3 :
                    format == 32993 && channel < 3 ? 2 - channel : channel;
                size_t offset = (size_t(row) * width + column) * channels + channel;
                if (type == 5126) {
                    std::memcpy(output + offset * 4, &rgba[component], 4);
                } else {
                    output[offset] = std::lround(std::clamp(rgba[component], 0.0f, 1.0f) * 255);
                }
            }
        }
    }
}

void Renderer::present(int width, int height, bool synchronize) {
    auto source = color(presentTarget);
    presentTarget = 0;
    if (!source) source = screen;
    if (width <= 0 || height <= 0) {
        if (recording) submit();
        return;
    }
    if (!swapchain || recreateSwapchain || synchronize != vsync || windowExtent.width != static_cast<uint32_t>(width)
        || windowExtent.height != static_cast<uint32_t>(height)) {
        if (recording) submit();
        resetSwapchain(width, height, synchronize);
        return;
    }
    Frame &frame = begin();
    uint32_t index = 0;
    VkResult acquired = vkAcquireNextImageKHR(device, swapchain, acquireTimeout, frame.acquire, VK_NULL_HANDLE, &index);
    if (acquired == VK_NOT_READY || acquired == VK_TIMEOUT) {
        missedAcquires++;
        submit();
        return;
    }
    if (acquired == VK_ERROR_OUT_OF_DATE_KHR) {
        recreateSwapchain = true;
        submit();
        return;
    }
    if (acquired == VK_SUBOPTIMAL_KHR) recreateSwapchain = true;
    else check(acquired, "Acquiring Vulkan backbuffer");
    endRendering();
    transition(*source, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL);
    frame.images.push_back(source);
    VkImage backbuffer = swapImages[index];
    barrier(backbuffer, VK_IMAGE_ASPECT_COLOR_BIT, 1,
        initializedImages[index] ? VK_IMAGE_LAYOUT_PRESENT_SRC_KHR : VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);
    VkImageBlit blit{};
    blit.srcSubresource = blit.dstSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1};
    blit.srcOffsets[1] = {static_cast<int>(source->width), static_cast<int>(source->height), 1};
    blit.dstOffsets[1] = {static_cast<int>(extent.width), static_cast<int>(extent.height), 1};
    vkCmdBlitImage(frame.command, source->handle, source->layout, backbuffer, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        1, &blit, VK_FILTER_NEAREST);
    barrier(backbuffer, VK_IMAGE_ASPECT_COLOR_BIT, 1, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, VK_IMAGE_LAYOUT_PRESENT_SRC_KHR);
    initializedImages[index] = true;
    VkSemaphore done = presented[index];
    submit(frame.acquire, done);
    VkPresentTimeGOOGLE time{nextPresentId++, 0};
    VkPresentTimesInfoGOOGLE timing{VK_STRUCTURE_TYPE_PRESENT_TIMES_INFO_GOOGLE};
    timing.swapchainCount = 1;
    timing.pTimes = &time;
    VkPresentInfoKHR presentation{VK_STRUCTURE_TYPE_PRESENT_INFO_KHR};
    presentation.pNext = displayTiming ? &timing : nullptr;
    presentation.waitSemaphoreCount = 1;
    presentation.pWaitSemaphores = &done;
    presentation.swapchainCount = 1;
    presentation.pSwapchains = &swapchain;
    presentation.pImageIndices = &index;
    VkResult result = vkQueuePresentKHR(queue, &presentation);
    if (result == VK_ERROR_OUT_OF_DATE_KHR || result == VK_SUBOPTIMAL_KHR) recreateSwapchain = true;
    else check(result, "Presenting Vulkan frame");
    if (result == VK_SUCCESS || result == VK_SUBOPTIMAL_KHR) presentedFrames++;
}

void Renderer::collectPresentationTiming() {
    if (!displayTiming || !swapchain) return;
    uint32_t count = 0;
    if (vkGetPastPresentationTimingGOOGLE(device, swapchain, &count, nullptr) != VK_SUCCESS || !count) return;
    presentationTimings.resize(count);
    auto status = vkGetPastPresentationTimingGOOGLE(device, swapchain, &count, presentationTimings.data());
    if (status != VK_SUCCESS && status != VK_INCOMPLETE) return;
    for (uint32_t index = 0; index < count; index++) {
        const auto &sample = presentationTimings[index];
        if (!sample.actualPresentTime || sample.presentID <= lastMeasuredPresentId) continue;
        actualPresents++;
        lastPresentedAt = std::max(lastPresentedAt, sample.actualPresentTime);
        lastMeasuredPresentId = sample.presentID;
    }
}
}

extern "C" {

JNIEXPORT jstring JNICALL Java_mcopt_legacy_DirectNative_initialize(JNIEnv *env, jclass, jlong window, jboolean greedy,
        jboolean measureDisplay) {
    jstring name = nullptr;
    nativeCall(env, [&] {
        @autoreleasepool {
            NSWindow *owner = (__bridge NSWindow *)(reinterpret_cast<void *>(window));
            if (!owner.contentView) throw std::runtime_error("Minecraft has no native window view");
            NSView *view = owner.contentView;
            CAMetalLayer *layer = [CAMetalLayer layer];
            layer.allowsNextDrawableTimeout = YES;
            layer.frame = view.bounds;
            layer.contentsScale = owner.backingScaleFactor;
            NSRect pixels = [view convertRectToBacking:view.bounds];
            layer.drawableSize = pixels.size;
            view.wantsLayer = YES;
            view.layer = layer;
            auto object = std::make_unique<Renderer>();
            object->greedyTerrain = greedy;
            object->measureDisplay = measureDisplay;
            object->initialize(layer);
            name = env->NewStringUTF(object->properties.deviceName);
            renderer = std::move(object);
        }
    });
    return name;
}

JNIEXPORT void JNICALL Java_mcopt_legacy_DirectNative_present(JNIEnv *env, jclass, jint width, jint height, jboolean vsync) {
    nativeCall(env, [&] {
        @autoreleasepool {
            gpu().present(width, height, vsync);
        }
    });
}

JNIEXPORT void JNICALL Java_mcopt_legacy_DirectNative_close(JNIEnv *, jclass) {
    @autoreleasepool {
        if (renderer && !renderer->readyToClose()) {
            std::fputs("meshnet: Vulkan queue stopped responding during shutdown\n", stderr);
            renderer.release();
        } else {
            renderer.reset();
        }
    }
}
JNIEXPORT void JNICALL Java_mcopt_legacy_DirectNative_presentTarget(JNIEnv *env, jclass, jint target) {
    nativeCall(env, [&] { gpu().presentTarget = target; });
}

JNIEXPORT void JNICALL Java_mcopt_legacy_DirectNative_texture(JNIEnv *env, jclass, jint id, jint width, jint height, jboolean depth) {
    nativeCall(env, [&] {
        if (width <= 0 || height <= 0) throw std::runtime_error("Invalid Vulkan texture size");
        uint32_t levels = 1;
        if (!depth) {
            for (uint32_t size = std::max(width, height); size > 1; size >>= 1) levels++;
        }
        gpu().textures[id].image = gpu().image(width, height, levels, depth);
    });
}

JNIEXPORT void JNICALL Java_mcopt_legacy_DirectNative_textureParameter(JNIEnv *env, jclass, jint id, jint key, jint value) {
    nativeCall(env, [&] {
        auto &texture = gpu().textures[id];
        switch (key) {
            case 10240: texture.mag = value; break;
            case 10241: texture.min = value; break;
            case 10242: texture.wrapS = value; break;
            case 10243: texture.wrapT = value; break;
            case 33085: texture.maxLevel = value; break;
        }
    });
}

JNIEXPORT void JNICALL Java_mcopt_legacy_DirectNative_uploadTexture(JNIEnv *env, jclass, jint id, jint level,
        jint x, jint y, jint width, jint height, jint rowBytes, jint format, jint type, jlong address) {
    nativeCall(env, [&] {
        auto found = gpu().textures.find(id);
        if (!address || found == gpu().textures.end() || !found->second.image) return;
        if (type != 5121 && type != 33639 && type != 32821) throw std::runtime_error("Unsupported Vulkan texture upload type " + std::to_string(type));
        auto &image = found->second.image;
        gpu().begin().images.push_back(image);
        gpu().upload(*image, level, x, y, width, height, rowBytes, format, reinterpret_cast<const uint8_t *>(address));
    });
}

JNIEXPORT void JNICALL Java_mcopt_legacy_DirectNative_deleteTexture(JNIEnv *env, jclass, jint id) {
    nativeCall(env, [&] { gpu().textures.erase(id); });
}

JNIEXPORT void JNICALL Java_mcopt_legacy_DirectNative_attach(JNIEnv *env, jclass, jint id, jint attachment, jint texture) {
    nativeCall(env, [&] {
        gpu().endRendering();
        auto &target = gpu().targets[id];
        if (attachment == 36064) target.color = texture;
        if (attachment == 36096) target.depth = texture;
        auto found = gpu().textures.find(texture);
        if (found != gpu().textures.end() && found->second.image) found->second.image->inverted = true;
    });
}

JNIEXPORT void JNICALL Java_mcopt_legacy_DirectNative_deleteTarget(JNIEnv *env, jclass, jint id) {
    nativeCall(env, [&] {
        gpu().endRendering();
        gpu().targets.erase(id);
    });
}

JNIEXPORT void JNICALL Java_mcopt_legacy_DirectNative_clear(JNIEnv *env, jclass, jint target, jint mask,
        jfloat red, jfloat green, jfloat blue, jfloat alpha, jdouble depth) {
    nativeCall(env, [&] { gpu().clear(target, mask, {{red, green, blue, alpha}}, depth); });
}

JNIEXPORT jintArray JNICALL Java_mcopt_legacy_DirectNative_prepareTerrain(JNIEnv *env, jclass, jobject data, jboolean greedy) {
    jintArray result = nullptr;
    nativeCall(env, [&] {
        jlong size = env->GetDirectBufferCapacity(data);
        if (size < 0 || size % sizeof(terrainmesh::Quad)) throw std::runtime_error("Invalid Vulkan terrain buffer");
        auto *source = env->GetDirectBufferAddress(data);
        if (size && !source) throw std::runtime_error("Missing Vulkan terrain buffer");
        static thread_local terrainmesh::Builder builder;
        terrainmesh::Result geometry;
        if (size) {
            geometry = builder.build(source, size, greedy, true);
            std::memcpy(source, builder.output.data(), geometry.vertices * terrainmesh::stride);
        }
        std::array<jint, 2 + terrainmesh::faceCount * 4> fields{};
        fields[0] = geometry.vertices;
        fields[1] = geometry.saved;
        for (size_t face = 0; face < geometry.groups.size(); face++) {
            const auto &group = geometry.groups[face];
            size_t start = 2 + face * 4;
            fields[start] = group.first;
            fields[start + 1] = group.count;
            fields[start + 2] = terrainmesh::asWord(group.minPlane);
            fields[start + 3] = terrainmesh::asWord(group.maxPlane);
        }
        result = env->NewIntArray(fields.size());
        if (result) env->SetIntArrayRegion(result, 0, fields.size(), fields.data());
    });
    return result;
}
JNIEXPORT void JNICALL Java_mcopt_legacy_DirectNative_uploadPreparedTerrain(JNIEnv *env, jclass, jint id, jobject data,
        jintArray metadata) {
    nativeCall(env, [&] {
        auto found = gpu().meshes.find(id);
        if (found == gpu().meshes.end() || !found->second.terrain) return;
        jlong size = env->GetDirectBufferCapacity(data);
        auto *source = env->GetDirectBufferAddress(data);
        std::array<jint, 2 + terrainmesh::faceCount * 4> fields{};
        if (env->GetArrayLength(metadata) != fields.size()) throw std::runtime_error("Invalid Vulkan terrain metadata");
        env->GetIntArrayRegion(metadata, 0, fields.size(), fields.data());
        if (size < 0 || (size && !source) || fields[0] < 0 || fields[1] < 0
            || (jlong(fields[0]) + fields[1]) * terrainmesh::stride != size) {
            throw std::runtime_error("Invalid Vulkan prepared terrain buffer");
        }
        terrainmesh::Result geometry;
        geometry.vertices = fields[0];
        geometry.saved = fields[1];
        for (size_t face = 0; face < geometry.groups.size(); face++) {
            size_t start = 2 + face * 4;
            geometry.groups[face] = {static_cast<uint32_t>(fields[start]), static_cast<uint32_t>(fields[start + 1]),
                terrainmesh::asFloat(fields[start + 2]), terrainmesh::asFloat(fields[start + 3])};
        }
        Mesh &mesh = found->second;
        gpu().commitTerrain(mesh, source, size, geometry);
    });
}
JNIEXPORT void JNICALL Java_mcopt_legacy_DirectNative_uploadBuffer(JNIEnv *env, jclass, jint id, jobject data) {
    nativeCall(env, [&] {
        auto &mesh = gpu().meshes[id];
        jlong size = env->GetDirectBufferCapacity(data);
        if (size < 0) throw std::runtime_error("Vulkan mesh upload requires a direct buffer");
        if (!size) {
            gpu().retireTerrain(mesh);
            mesh.buffer.reset();
            return;
        }
        auto source = env->GetDirectBufferAddress(data);
        if (!source) throw std::runtime_error("Vulkan mesh upload has no buffer address");
        if (mesh.terrain) {
            gpu().uploadTerrain(mesh, source, size);
            return;
        }
        if (!mesh.buffer || mesh.buffer.use_count() > 1 || mesh.buffer->size < static_cast<VkDeviceSize>(size)) {
            mesh.buffer = gpu().buffer(size, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_VERTEX_BUFFER_BIT);
        }
        std::memcpy(mesh.buffer->data, source, size);
        if (mesh.buffer->size - size < 4) std::memset(mesh.buffer->data + size, 0, mesh.buffer->size - size);
        mesh.buffer->used = size;
    });
}

JNIEXPORT void JNICALL Java_mcopt_legacy_DirectNative_uploadDistantTerrain(JNIEnv *env, jclass, jint id,
        jint x, jint z, jfloat minY, jfloat maxY, jobject data) {
    nativeCall(env, [&] {
        auto *source = env->GetDirectBufferAddress(data);
        jlong size = env->GetDirectBufferCapacity(data);
        if (!source || size <= 0 || size > 448 * terrainmesh::stride || size % (4 * terrainmesh::stride))
            throw std::runtime_error("Invalid Vulkan distant terrain");
        auto range = gpu().storeTerrain(source, size, false);
        auto found = gpu().distantMeshes.find(id);
        if (found != gpu().distantMeshes.end()) gpu().retireTerrain(found->second.range);
        gpu().distantMeshes.insert_or_assign(id, DistantMesh{range, x, z, minY, maxY});
    });
}
JNIEXPORT void JNICALL Java_mcopt_legacy_DirectNative_drawDistantTerrain(JNIEnv *env, jclass, jobject state,
        jobject columns, jint count, jdouble x, jdouble y, jdouble z) {
    nativeCall(env, [&] {
        auto *data = env->GetDirectBufferAddress(state);
        auto *ids = static_cast<const int32_t *>(env->GetDirectBufferAddress(columns));
        if (data && ids && count > 0) gpu().distant(DrawState(data), ids, count, x, y, z);
    });
}
JNIEXPORT void JNICALL Java_mcopt_legacy_DirectNative_deleteBuffer(JNIEnv *env, jclass, jint id) {
    nativeCall(env, [&] {
        auto distant = gpu().distantMeshes.find(id);
        if (distant != gpu().distantMeshes.end()) {
            gpu().retireTerrain(distant->second.range);
            gpu().distantMeshes.erase(distant);
            return;
        }
        auto mesh = gpu().meshes.find(id);
        if (mesh != gpu().meshes.end()) {
            gpu().retireTerrain(mesh->second);
            gpu().meshes.erase(mesh);
        }
    });
}

JNIEXPORT void JNICALL Java_mcopt_legacy_DirectNative_draw(JNIEnv *env, jclass, jobject vertices,
        jint first, jint count, jint mode, jint id, jobject state) {
    nativeCall(env, [&] {
        auto bytes = vertices ? env->GetDirectBufferAddress(vertices) : nullptr;
        auto drawState = env->GetDirectBufferAddress(state);
        if (!drawState || (vertices && !bytes)) throw std::runtime_error("Vulkan draw requires direct buffers");
        gpu().draw(bytes, first, count, mode, id, DrawState(drawState));
    });
}

JNIEXPORT void JNICALL Java_mcopt_legacy_DirectNative_terrainOrigin(JNIEnv *env, jclass, jint id, jint layer,
        jint x, jint y, jint z) {
    nativeCall(env, [&] {
        if (layer < 0 || layer >= static_cast<int>(gpu().visibility.size())) return;
        auto &mesh = gpu().meshes[id];
        if (mesh.terrain && mesh.origin != std::array<int, 3>{x, y, z}) gpu().retireTerrain(mesh);
        mesh.terrain = true;
        mesh.layer = layer;
        mesh.origin = {x, y, z};
        if (mesh.buffer) {
            gpu().uploadTerrain(mesh, mesh.buffer->data, mesh.buffer->used);
            mesh.buffer.reset();
        }
    });
}

JNIEXPORT void JNICALL Java_mcopt_legacy_DirectNative_terrainVisibility(JNIEnv *env, jclass, jobject sections, jint count) {
    nativeCall(env, [&] {
        auto *data = static_cast<const int32_t *>(env->GetDirectBufferAddress(sections));
        auto &visibility = gpu().visibility;
        for (auto &layer : visibility) layer.clear();
        if (count <= 0 || !data) return;
        for (int index = 0; index < count; index++) {
            for (size_t layer = 0; layer < visibility.size(); layer++) {
                int id = data[index * visibility.size() + layer];
                if (id >= 0) visibility[layer].push_back(id);
            }
        }
    });
}
JNIEXPORT void JNICALL Java_mcopt_legacy_DirectNative_terrainDraw(JNIEnv *env, jclass, jint layer, jobject state,
        jdouble x, jdouble y, jdouble z, jint distance) {
    nativeCall(env, [&] {
        auto address = env->GetDirectBufferAddress(state);
        if (!address) throw std::runtime_error("Vulkan terrain state is unavailable");
        gpu().terrain(layer, DrawState(address), x, y, z, distance);
    });
}

JNIEXPORT void JNICALL Java_mcopt_legacy_DirectNative_copyDepth(JNIEnv *env, jclass, jint source, jint destination) {
    nativeCall(env, [&] { gpu().copyDepth(source, destination); });
}

JNIEXPORT void JNICALL Java_mcopt_legacy_DirectNative_readTexture(JNIEnv *env, jclass, jint id, jint level,
        jint format, jint type, jlong address) {
    nativeCall(env, [&] {
        auto found = gpu().textures.find(id);
        if (found == gpu().textures.end() || !found->second.image) return;
        auto &image = *found->second.image;
        if (level < 0 || static_cast<uint32_t>(level) >= image.levels) throw std::runtime_error("Invalid Vulkan readback mip");
        gpu().download(image, level, 0, 0, mipSize(image.width, level), mipSize(image.height, level),
            format, type, reinterpret_cast<uint8_t *>(address));
    });
}

JNIEXPORT void JNICALL Java_mcopt_legacy_DirectNative_readPixels(JNIEnv *env, jclass, jint target, jint x, jint y,
        jint width, jint height, jint format, jint type, jlong address) {
    nativeCall(env, [&] {
        auto image = format == 6402 ? gpu().depth(target) : gpu().color(target);
        if (image) gpu().download(*image, 0, x, y, width, height, format, type, reinterpret_cast<uint8_t *>(address));
    });
}

JNIEXPORT void JNICALL Java_mcopt_legacy_DirectNative_effect(JNIEnv *env, jclass, jint id, jbyteArray vertex, jbyteArray fragment) {
    nativeCall(env, [&] {
        auto load = [&](jbyteArray bytes) {
            std::vector<uint8_t> code(env->GetArrayLength(bytes));
            env->GetByteArrayRegion(bytes, 0, code.size(), reinterpret_cast<jbyte *>(code.data()));
            VkShaderModule module = gpu().shader(code.data(), code.size());
            gpu().effectModules.push_back(module);
            return module;
        };
        auto &effect = gpu().effects[id];
        effect.vertex = load(vertex);
        effect.fragment = load(fragment);
    });
}

JNIEXPORT void JNICALL Java_mcopt_legacy_DirectNative_effectData(JNIEnv *env, jclass, jint id, jobject data, jintArray units) {
    nativeCall(env, [&] {
        auto &effect = gpu().effects.at(id);
        auto address = static_cast<const uint8_t *>(env->GetDirectBufferAddress(data));
        int count = env->GetArrayLength(units);
        if (!address || count > static_cast<int>(maxTextures)) throw std::runtime_error("Unsupported Vulkan effect inputs");
        effect.uniforms.assign(address, address + env->GetDirectBufferCapacity(data));
        effect.units.resize(count);
        env->GetIntArrayRegion(units, 0, count, effect.units.data());
    });
}

JNIEXPORT void JNICALL Java_mcopt_legacy_DirectNative_deleteEffect(JNIEnv *env, jclass, jint id) {
    nativeCall(env, [&] { gpu().effects.erase(id); });
}

JNIEXPORT jdoubleArray JNICALL Java_mcopt_legacy_DirectNative_frameStats(JNIEnv *env, jclass) {
    jdoubleArray result = env->NewDoubleArray(10);
    if (result && renderer) {
        renderer->collectPresentationTiming();
        double stats[] = {static_cast<double>(renderer->sourceTerrainVertices), renderer->fenceMilliseconds,
            static_cast<double>(renderer->savedTerrainVertices), static_cast<double>(renderer->terrainCount),
            static_cast<double>(renderer->terrainCommands), static_cast<double>(renderer->terrainPages.size()),
            static_cast<double>(renderer->presentedFrames), static_cast<double>(renderer->missedAcquires),
            static_cast<double>(renderer->actualPresents), static_cast<double>(renderer->lastPresentedAt)};
        env->SetDoubleArrayRegion(result, 0, 10, stats);
    }
    return result;
}

}
