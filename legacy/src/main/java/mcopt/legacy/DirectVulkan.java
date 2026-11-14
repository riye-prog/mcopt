package mcopt.legacy;

import com.mojang.blaze3d.vertex.VertexFormat;
import com.mojang.blaze3d.vertex.VertexFormatElement;
import com.mojang.math.Matrix4f;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.FloatBuffer;
import java.nio.IntBuffer;
import java.util.Arrays;
import org.lwjgl.glfw.GLFWNativeCocoa;
import org.lwjgl.system.MemoryUtil;

public final class DirectVulkan {
    public static final boolean GREEDY_TERRAIN = Boolean.parseBoolean(System.getProperty("meshnet.vulkan.greedy", "true"));
    public static final DirectMatrices MODEL = new DirectMatrices();
    public static final DirectMatrices PROJECTION = new DirectMatrices();
    private static final DirectMatrices[] TEXTURE = {new DirectMatrices(), new DirectMatrices(),
                                                     new DirectMatrices()};
    private static final ByteBuffer STATE = ByteBuffer.allocateDirect(1024).order(ByteOrder.nativeOrder());
    private static final float[] COLOR = {1, 1, 1, 1}, FOG_COLOR = {0, 0, 0, 0}, FOG = {0, 1, 1, 0.1f};
    private static final float[][] LIGHTS = {{0, 1, 0, 0.6f}, {0, 1, 0, 0.6f}};
    private static final float[] AMBIENT = {0.4f, 0.4f, 0.4f, 1};
    private static final float[][] COORDS = new float[3][4];
    private static final int[] TEXTURES = new int[16];
    private static final boolean[] TEXTURING = new boolean[16];
    private static int nextId = 1, activeTexture, matrixMode = 5888, boundBuffer, target, readTarget,
                       drawTarget;
    private static int alphaFunction = 516, fogMode = 2048, depthFunction = 513, sourceRgb = 1,
                       destinationRgb, sourceAlpha = 1, destinationAlpha, equation = 32774, colorMask = 15;
    private static int viewportX, viewportY, viewportWidth = 1, viewportHeight = 1, unpackWidth, unpackX,
                                             unpackY, unpackAlignment = 4;
    private static boolean logicEnabled;
    private static int logicOperation = 5379;
    private static final java.util.Deque<Runnable> ATTRIBUTES = new java.util.ArrayDeque<>();
    private static boolean initialized, vsync = true, alphaTest, lighting, depthTest, depthWrite = true,
                                        blend, cull, fog, polygonOffset, outline, texGen;
    private static float offsetFactor, offsetUnits;
    private static VertexFormat currentFormat;
    private static String deviceName = "uninitialized";
    private DirectVulkan() {}
    public static boolean active() { return LegacyVulkanBackend.requested(); }
    public static boolean ready() { return initialized; }
    public static String renderer() { return deviceName + " Vulkan (MoltenVK)"; }
    public static int id() { return nextId++; }
    public static void initialize(long window) {
        if (!active() || initialized)
            return;
        deviceName = DirectNative.initialize(GLFWNativeCocoa.glfwGetCocoaWindow(window), GREEDY_TERRAIN,
            Boolean.getBoolean("meshnet.directBenchmark"));
        initialized = true;
        System.out.println("meshnet: direct Vulkan via MoltenVK on " + deviceName + "; GLFW_NO_API");
    }
    public static void close() {
        if (initialized) {
            DirectNative.close();
            initialized = false;
        }
    }
    public static void present(int width, int height) {
        if (initialized)
            DirectNative.present(width, height, vsync);
    }
    public static void vsync(boolean enabled) { vsync = enabled; }
    public static void format(VertexFormat format) { currentFormat = format; }
    public static void bindBuffer(int kind, int id) {
        if (kind == 34962)
            boundBuffer = id;
    }
    public static void uploadBuffer(int kind, ByteBuffer data, int usage) {
        if (kind == 34962)
            DirectNative.uploadBuffer(boundBuffer, data.slice());
    }
    public static void draw(int mode, int first, int count) {
        if (count > 0 && currentFormat != null)
            DirectNative.draw(null, first, count, mode, boundBuffer, state(currentFormat));
    }
    public static void draw(ByteBuffer data, int mode, VertexFormat format, int count) {
        if (count > 0)
            DirectNative.draw(data, 0, count, mode, 0, state(format));
    }
    public static void deleteBuffer(int id) { DirectNative.deleteBuffer(id); }
    public static void activeTexture(int texture) {
        activeTexture = texture - 33984;
        if (activeTexture < 0 || activeTexture >= TEXTURES.length)
            throw new IllegalArgumentException("texture unit " + activeTexture);
    }
    public static void texturing(boolean enabled) { TEXTURING[activeTexture] = enabled; }
    public static void bindTexture(int id) { TEXTURES[activeTexture] = id; }
    public static int boundTexture() { return TEXTURES[activeTexture]; }
    public static void deleteTexture(int id) {
        DirectNative.deleteTexture(id);
        for (int i = 0; i < TEXTURES.length; i++)
            if (TEXTURES[i] == id)
                TEXTURES[i] = 0;
    }
    public static void texParameter(int kind, int parameter, int value) {
        DirectNative.textureParameter(boundTexture(), parameter, value);
    }
    public static void texParameter(int kind, int parameter, float value) {
        texParameter(kind, parameter, (int)value);
    }
    public static void image(int kind, int level, int internal, int width, int height, int border, int format,
                             int type, IntBuffer data) {
        if (level == 0)
            DirectNative.texture(boundTexture(), width, height, internal == 6402);
        if (data != null)
            DirectNative.uploadTexture(boundTexture(), level, 0, 0, width, height, width * 4, format, type,
                                       MemoryUtil.memAddress(data));
    }
    public static void upload(int kind, int level, int x, int y, int width, int height, int format, int type,
                              long address) {
        int components = format == 6408 || format == 32993   ? 4
                         : format == 6407                    ? 3
                         : format == 33319 || format == 6410 ? 2
                                                             : 1;
        int rowBytes = (unpackWidth == 0 ? width : unpackWidth) * components;
        rowBytes = (rowBytes + unpackAlignment - 1) & -unpackAlignment;
        DirectNative.uploadTexture(boundTexture(), level, x, y, width, height, rowBytes, format, type,
                                   address + (long)unpackY * rowBytes + (long)unpackX * components);
    }
    public static void pixelStore(int parameter, int value) {
        switch (parameter) {
        case 3314:
            unpackWidth = value;
            break;
        case 3315:
            unpackY = value;
            break;
        case 3316:
            unpackX = value;
            break;
        case 3317:
            unpackAlignment = value;
            break;
        default:
            break;
        }
    }
    public static void readTexture(int kind, int level, int format, int type, long address) {
        DirectNative.readTexture(boundTexture(), level, format, type, address);
    }
    public static void readPixels(int x, int y, int width, int height, int format, int type,
                                  ByteBuffer bytes) {
        int channels = format == 6408 || format == 32993   ? 4
                       : format == 6407                    ? 3
                       : format == 33319 || format == 6410 ? 2
                                                           : 1;
        long required = (long)width * height * channels * (type == 5126 ? 4 : 1);
        if (required < 0 || required > bytes.remaining())
            throw new IllegalArgumentException("readback buffer is too small");
        DirectNative.readPixels(target, x, y, width, height, format, type, MemoryUtil.memAddress(bytes));
    }
    public static void bindTarget(int kind, int id) {
        if (kind == 36008)
            readTarget = id;
        else if (kind == 36009)
            drawTarget = id;
        else
            target = readTarget = drawTarget = id;
    }
    public static void attach(int kind, int attachment, int textureKind, int texture, int level) {
        DirectNative.attach(target, attachment, texture);
    }
    public static void copyDepth() { DirectNative.copyDepth(readTarget, drawTarget); }
    public static void clear(int mask, boolean check) {
        DirectNative.clear(target, mask, clearRed, clearGreen, clearBlue, clearAlpha, clearDepth);
    }
    private static float clearRed, clearGreen, clearBlue, clearAlpha;
    private static double clearDepth = 1;
    public static void clearColor(float red, float green, float blue, float alpha) {
        clearRed = red;
        clearGreen = green;
        clearBlue = blue;
        clearAlpha = alpha;
    }
    public static void clearDepth(double value) { clearDepth = value; }
    public static void color(float red, float green, float blue, float alpha) {
        COLOR[0] = red;
        COLOR[1] = green;
        COLOR[2] = blue;
        COLOR[3] = alpha;
    }
    public static void clearCurrentColor() {}
    public static void alphaTest(boolean enabled) { alphaTest = enabled; }
    public static void alpha(int function, float reference) {
        alphaFunction = function;
        FOG[3] = reference;
    }
    public static void lighting(boolean enabled) { lighting = enabled; }
    public static void light(int light, int parameter, FloatBuffer values) {
        int index = light - 16384;
        if (index < 0 || index > 1)
            return;
        if (parameter == 4611)
            for (int i = 0; i < 3; i++)
                LIGHTS[index][i] = values.get(values.position() + i);
        else if (parameter == 4609)
            LIGHTS[index][3] = values.get(values.position());
    }
    public static void ambient(int parameter, FloatBuffer values) {
        for (int i = 0; i < 4; i++)
            AMBIENT[i] = values.get(values.position() + i);
    }
    public static void depthTest(boolean enabled) { depthTest = enabled; }
    public static void depthFunc(int function) { depthFunction = function; }
    public static void depthMask(boolean enabled) { depthWrite = enabled; }
    public static void blend(boolean enabled) { blend = enabled; }
    public static void blendFunc(int source, int destination) {
        blendFunc(source, destination, source, destination);
    }
    public static void blendFunc(int sr, int dr, int sa, int da) {
        sourceRgb = sr;
        destinationRgb = dr;
        sourceAlpha = sa;
        destinationAlpha = da;
    }
    public static void blendEquation(int value) { equation = value; }
    public static void fog(boolean enabled) { fog = enabled; }
    public static void fogMode(int value) { fogMode = value; }
    public static void fogDensity(float value) { FOG[2] = value; }
    public static void fogStart(float value) { FOG[0] = value; }
    public static void fogEnd(float value) { FOG[1] = value; }
    public static void fogColor(int parameter, float[] values) {
        if (parameter == 2918)
            System.arraycopy(values, 0, FOG_COLOR, 0, 4);
    }
    public static void cull(boolean enabled) { cull = enabled; }
    public static void polygonOffset(boolean enabled) { polygonOffset = enabled; }
    public static void polygonOffset(float factor, float units) {
        offsetFactor = factor;
        offsetUnits = units;
    }
    public static void viewport(int x, int y, int width, int height) {
        viewportX = x;
        viewportY = y;
        viewportWidth = width;
        viewportHeight = height;
    }
    public static void colorMask(boolean r, boolean g, boolean b, boolean a) {
        colorMask = (r ? 1 : 0) | (g ? 2 : 0) | (b ? 4 : 0) | (a ? 8 : 0);
    }
    public static void coordinates(int unit, float x, float y) {
        int index = unit - 33984;
        if (index >= 0 && index < 3) {
            COORDS[index][0] = x;
            COORDS[index][1] = y;
        }
    }
    public static void texEnv(int kind, int parameter, int value) {
        if (activeTexture == 0 && parameter == 8704)
            outline = value == 34160;
    }
    public static void outline(boolean enabled) { outline = enabled; }
    public static void texGen(boolean enabled) { texGen = enabled; }
    public static void matrixMode(int mode) { matrixMode = mode; }
    public static DirectMatrices matrix() {
        return matrixMode == 5889 ? PROJECTION
        : matrixMode == 5890      ? TEXTURE[Math.min(activeTexture, 2)]
                                  : MODEL;
    }
    public static void getMatrix(int name, FloatBuffer out) {
        float[] matrix = (name == 2983   ? PROJECTION
                          : name == 2984 ? TEXTURE[Math.min(activeTexture, 2)]
                                         : MODEL)
                             .values();
        for (int i = 0; i < 16; i++)
            out.put(out.position() + i, matrix[i]);
    }
    public static void multiply(FloatBuffer in) {
        float[] values = new float[16];
        for (int i = 0; i < 16; i++)
            values[i] = in.get(in.position() + i);
        matrix().multiply(values);
    }
    public static void multiply(Matrix4f in) {
        FloatBuffer buffer = STATE.asFloatBuffer();
        in.store(buffer);
        float[] values = new float[16];
        for (int i = 0; i < 16; i++)
            values[i] = buffer.get(i);
        matrix().multiply(values);
    }
    public static void logic(boolean enabled) { logicEnabled = enabled; }
    public static void logicOperation(int operation) { logicOperation = operation; }
    public static void pushLighting() {
        boolean previousLighting = lighting;
        float[] first = LIGHTS[0].clone(), second = LIGHTS[1].clone(), ambient = AMBIENT.clone();
        ATTRIBUTES.push(() -> {
            lighting = previousLighting;
            System.arraycopy(first, 0, LIGHTS[0], 0, 4);
            System.arraycopy(second, 0, LIGHTS[1], 0, 4);
            System.arraycopy(ambient, 0, AMBIENT, 0, 4);
        });
    }
    public static void pushTextures() {
        int[] previous = TEXTURES.clone();
        boolean[] enabled = TEXTURING.clone();
        int unit = activeTexture;
        boolean previousOutline = outline, previousTexGen = texGen;
        ATTRIBUTES.push(() -> {
            System.arraycopy(previous, 0, TEXTURES, 0, TEXTURES.length);
            System.arraycopy(enabled, 0, TEXTURING, 0, TEXTURING.length);
            activeTexture = unit;
            outline = previousOutline;
            texGen = previousTexGen;
        });
    }
    public static void popAttributes() {
        if (ATTRIBUTES.isEmpty())
            throw new IllegalStateException("attribute stack underflow");
        ATTRIBUTES.pop().run();
    }
    public static void normal(float x, float y, float z) {
        normalX = x;
        normalY = y;
        normalZ = z;
    }
    private static float normalX, normalY, normalZ = 1;
    private static void put(int offset, float[] values) {
        for (int i = 0; i < values.length; i++)
            STATE.putFloat(offset + i * 4, values[i]);
    }
    public static ByteBuffer state(VertexFormat format) {
        put(0, DirectMatrices.product(PROJECTION.values(), MODEL.values()));
        put(64, MODEL.values());
        for (int i = 0; i < 3; i++)
            put(128 + i * 64, TEXTURE[i].values());
        put(320, COLOR);
        put(336, FOG_COLOR);
        put(352, FOG);
        put(368, LIGHTS[0]);
        put(384, LIGHTS[1]);
        put(400, AMBIENT);
        for (int i = 0; i < 3; i++)
            put(416 + i * 16, COORDS[i]);
        int mask = 0;
        for (int i = 0; i < 3; i++)
            if (TEXTURING[i])
                mask |= 1 << i;
        STATE.putInt(464, mask);
        STATE.putInt(468, alphaTest ? alphaFunction : 0);
        STATE.putInt(472, fog ? fogMode : 0);
        STATE.putInt(476, (lighting ? 1 : 0) | (outline ? 2 : 0) | (texGen ? 4 : 0));
        for (int i = 0; i < 6; i++) {
            STATE.putInt(480 + i * 16, -1);
            STATE.putInt(484 + i * 16, 0);
            STATE.putInt(488 + i * 16, 0);
        }
        int offset = 0;
        for (VertexFormatElement element : format.getElements()) {
            int index = -1;
            switch (element.getUsage()) {
            case POSITION:
                index = 0;
                break;
            case COLOR:
                index = 1;
                break;
            case UV:
                index = 2 + element.getIndex();
                break;
            case NORMAL:
                index = 5;
                break;
            default:
                break;
            }
            if (index >= 0 && index < 6) {
                STATE.putInt(480 + index * 16, offset);
                STATE.putInt(484 + index * 16, element.getType().getGlType());
                STATE.putInt(488 + index * 16, element.getByteSize() / element.getType().getSize());
            }
            offset += element.getByteSize();
        }
        STATE.putFloat(576, normalX);
        STATE.putFloat(580, normalY);
        STATE.putFloat(584, normalZ);
        int[] pipeline = {target,
                          blend ? 1 : 0,
                          sourceRgb,
                          destinationRgb,
                          sourceAlpha,
                          destinationAlpha,
                          equation,
                          depthTest ? 1 : 0,
                          depthFunction,
                          depthWrite ? 1 : 0,
                          cull ? 1 : 0,
                          colorMask,
                          polygonOffset ? 1 : 0,
                          Float.floatToRawIntBits(offsetFactor),
                          Float.floatToRawIntBits(offsetUnits),
                          0,
                          0,
                          0,
                          0,
                          0,
                          viewportX,
                          viewportY,
                          viewportWidth,
                          viewportHeight,
                          format.getVertexSize(),
                          0,
                          DirectPrograms.current(),
                          logicEnabled ? logicOperation : 0};
        for (int i = 0; i < pipeline.length; i++)
            STATE.putInt(640 + i * 4, pipeline[i]);
        for (int i = 0; i < TEXTURES.length; i++)
            STATE.putInt(768 + i * 4, TEXTURES[i]);
        DirectPrograms.prepare();
        return STATE;
    }
    public static String getString(int name) {
        return name == 7936 ? "Apple" : name == 7938 ? "Vulkan (Minecraft 1.16.1 direct backend)" : renderer();
    }
    public static int getInteger(int name) {
        return name == 3379 ? 16384 : name == 34016 ? 33984 + activeTexture : 0;
    }
}
