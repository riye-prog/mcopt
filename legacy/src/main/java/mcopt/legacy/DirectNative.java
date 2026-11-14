package mcopt.legacy;

import java.nio.ByteBuffer;

public final class DirectNative {
    public static native String initialize(long window, boolean greedyTerrain, boolean measureDisplay);
    public static native void present(int width, int height, boolean vsync);
    public static native void close();
    public static native double[] frameStats();
    public static native void effect(int id, byte[] vertex, byte[] fragment);
    public static native void effectData(int id, ByteBuffer data, int[] units);
    public static native void deleteEffect(int id);
    public static native void texture(int id, int width, int height, boolean depth);
    public static native void textureParameter(int id, int key, int value);
    public static native void uploadTexture(int id, int level, int x, int y, int width, int height,
                                            int rowBytes, int format, int type, long address);
    public static native void deleteTexture(int id);
    public static native void attach(int target, int attachment, int texture);
    public static native void deleteTarget(int target);
    public static native void clear(int target, int mask, float red, float green, float blue, float alpha,
                                    double depth);
    public static native void draw(ByteBuffer vertices, int first, int count, int mode, int buffer,
                                   ByteBuffer state);
    public static native void uploadBuffer(int id, ByteBuffer vertices);
    public static native int[] prepareTerrain(ByteBuffer vertices, boolean greedy);
    public static native void uploadPreparedTerrain(int id, ByteBuffer vertices, int[] geometry);
    public static native void uploadDistantTerrain(int id, int x, int z, float minY, float maxY, ByteBuffer vertices);
    public static native void drawDistantTerrain(ByteBuffer state, ByteBuffer columns, int count,
        double x, double y, double z);
    public static native void presentTarget(int target);
    public static native void deleteBuffer(int id);
    public static native void readTexture(int id, int level, int format, int type, long address);
    public static native void copyDepth(int source, int destination);
    public static native void readPixels(int target, int x, int y, int width, int height, int format,
                                         int type, long address);
    public static native void terrainOrigin(int buffer, int layer, int x, int y, int z);
    public static native void terrainVisibility(ByteBuffer visibility, int sections);
    public static native void terrainDraw(int layer, ByteBuffer state, double x, double y, double z,
                                          int distance);
}
