package mcopt.legacy;
import com.mojang.blaze3d.systems.RenderSystem;
import com.mojang.blaze3d.vertex.DefaultVertexFormat;
import com.mojang.blaze3d.vertex.VertexBuffer;
import com.mojang.math.Matrix4f;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicReference;
import it.unimi.dsi.fastutil.longs.LongOpenHashSet;
import net.minecraft.client.Minecraft;
import net.minecraft.client.renderer.RenderType;
import net.minecraft.client.renderer.chunk.ChunkRenderDispatcher;
public final class DirectTerrain {
    private static final
        Map<AtomicReference<ChunkRenderDispatcher.CompiledChunk>, ChunkRenderDispatcher.RenderChunk> CHUNKS =
            new ConcurrentHashMap<>();
    private static final ByteBuffer EMPTY = ByteBuffer.allocateDirect(0);
    private static long frames;
    public static final boolean FAST = Boolean.parseBoolean(System.getProperty("meshnet.vulkan.fast", "true"));
    private static final int DETAIL_DISTANCE = Math.max(4, Integer.getInteger("meshnet.vulkan.detailDistance", 8));
    private static final DistantTerrain DISTANT = new DistantTerrain();
    private static final LongOpenHashSet DETAILED_COLUMNS = new LongOpenHashSet();
    private static final RenderType[] LAYERS = {
        RenderType.solid(), RenderType.cutoutMipped(), RenderType.cutout(), RenderType.translucent()
    };
    public static int detailDistance(int distance) {
        Minecraft minecraft = Minecraft.getInstance();
        if (!FAST || minecraft == null || minecraft.level == null ||
            minecraft.level.dimension() != net.minecraft.world.level.Level.OVERWORLD) return distance;
        return Math.min(distance, DETAIL_DISTANCE);
    }
    private static ByteBuffer visibility = ByteBuffer.allocateDirect(4096).order(ByteOrder.nativeOrder());
    public static int layer(RenderType layer) {
        return layer == RenderType.solid()   ? 0
        : layer == RenderType.cutoutMipped() ? 1
        : layer == RenderType.cutout()       ? 2
                                             : 3;
    }
    public static void track(ChunkRenderDispatcher.RenderChunk chunk) {
        if (!DirectVulkan.active())
            return;
        CHUNKS.put(chunk.compiled, chunk);
        for (RenderType layer : RenderType.chunkBufferLayers()) {
            DirectBufferAccess buffer = (DirectBufferAccess)chunk.getBuffer(layer);
            buffer.meshnet$markTerrain(layer(layer));
            int id = buffer.meshnet$bufferId();
            DirectNative.terrainOrigin(
                id, layer(layer),
                chunk.getOrigin().getX(), chunk.getOrigin().getY(), chunk.getOrigin().getZ());
        }
    }
    public static void published(AtomicReference<?> reference, Object value) {
        if (!DirectVulkan.active())
            return;
        ChunkRenderDispatcher.RenderChunk chunk = CHUNKS.get(reference);
        if (chunk == null || !(value instanceof ChunkRenderDispatcher.CompiledChunk))
            return;
        ChunkRenderDispatcher.CompiledChunk compiled = (ChunkRenderDispatcher.CompiledChunk)value;
        Runnable update = () -> {
            if (chunk.compiled.get() != compiled)
                return;
            for (RenderType layer : RenderType.chunkBufferLayers())
                if (compiled.isEmpty(layer))
                    DirectNative.uploadBuffer(((DirectBufferAccess)chunk.getBuffer(layer)).meshnet$bufferId(),
                                              EMPTY);
        };
        if (RenderSystem.isOnRenderThread())
            update.run();
        else
            RenderSystem.recordRenderCall(update::run);
    }
    public static void render(RenderType layer, Matrix4f view, double x, double y, double z) {
        DirectVulkan.MODEL.push();
        DirectVulkan.MODEL.reset();
        DirectVulkan.multiply(view);
        try {
            int distance = Minecraft.getInstance().options.renderDistance;
            int near = detailDistance(distance);
            int layerIndex = layer(layer);
            ByteBuffer state = DirectVulkan.state(DefaultVertexFormat.BLOCK);
            if (layerIndex == 0 && near < distance) {
                DISTANT.update(x, z, near, distance);
                DISTANT.draw(state, x, y, z, distance);
            }
            DirectNative.terrainDraw(layerIndex, state, x, y, z, distance);
            frames++;
        } finally {
            DirectVulkan.MODEL.pop();
        }
    }
    public static void visible(List<?> chunks) {
        if (!DirectVulkan.active())
            return;
        int bytes = chunks.size() * LAYERS.length * Integer.BYTES;
        if (visibility.capacity() < bytes)
            visibility = ByteBuffer.allocateDirect(Integer.highestOneBit(bytes - 1) * 2).order(ByteOrder.nativeOrder());
        visibility.clear();
        DETAILED_COLUMNS.clear();
        boolean distant = detailDistance(Minecraft.getInstance().options.renderDistance) <
            Minecraft.getInstance().options.renderDistance;
        for (Object info : chunks) {
            ChunkRenderDispatcher.RenderChunk chunk = ((DirectChunkInfoAccess)info).meshnet$chunk();
            ChunkRenderDispatcher.CompiledChunk compiled = chunk.getCompiledChunk();
            if (distant && !compiled.hasNoRenderableLayers()) {
                DETAILED_COLUMNS.add(net.minecraft.world.level.ChunkPos.asLong(chunk.getOrigin().getX() >> 4,
                    chunk.getOrigin().getZ() >> 4));
            }
            for (RenderType layer : LAYERS) {
                visibility.putInt(compiled.isEmpty(layer) ? -1 :
                    ((DirectBufferAccess)chunk.getBuffer(layer)).meshnet$bufferId());
            }
        }
        DirectNative.terrainVisibility(visibility, chunks.size());
    }
    public static long frames() { return frames; }
    static LongOpenHashSet detailedColumns() { return DETAILED_COLUMNS; }
    public static void invalidateDistant(int x, int z) {
        if (FAST) DISTANT.invalidate(x, z);
    }
    public static void clear() {
        CHUNKS.clear();
        if (DirectVulkan.ready()) DISTANT.clear();
    }
}
