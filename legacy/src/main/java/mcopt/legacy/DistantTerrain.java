package mcopt.legacy;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.Iterator;
import java.util.IdentityHashMap;
import java.util.List;
import java.util.Random;
import java.util.Map;
import java.util.Arrays;
import it.unimi.dsi.fastutil.longs.Long2ObjectMap;
import it.unimi.dsi.fastutil.longs.Long2ObjectOpenHashMap;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.client.renderer.BiomeColors;
import net.minecraft.client.renderer.block.model.BakedQuad;
import net.minecraft.client.renderer.texture.TextureAtlasSprite;
import net.minecraft.client.resources.model.BakedModel;
import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.tags.FluidTags;
import net.minecraft.world.level.ChunkPos;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.tags.BlockTags;
import net.minecraft.world.level.chunk.ChunkStatus;
import net.minecraft.world.level.chunk.LevelChunk;
import net.minecraft.world.level.levelgen.Heightmap;

public final class DistantTerrain {
    private static final int NEAR_STEP = 2;
    private static final int FAR_STEP = 4;
    private static final int MAX_POINTS = 16 / NEAR_STEP + 1;
    private static final int STRIDE = 32;
    private static final int MAX_NEW_COLUMNS = 40;
    private final Long2ObjectOpenHashMap<Column> columns = new Long2ObjectOpenHashMap<>();
    private ByteBuffer visible = ByteBuffer.allocateDirect(4096).order(ByteOrder.nativeOrder());
    private ByteBuffer visibleWater = ByteBuffer.allocateDirect(4096).order(ByteOrder.nativeOrder());
    private static final int FOLIAGE_INTERVAL = 4;
    private static final int MAX_QUADS = (MAX_POINTS - 1) * (MAX_POINTS - 1) + 3 * 16;
    private final ByteBuffer mesh = ByteBuffer.allocateDirect(MAX_QUADS * 4 * STRIDE)
        .order(ByteOrder.nativeOrder());
    private final ByteBuffer waterMesh = ByteBuffer.allocateDirect((MAX_POINTS - 1) * (MAX_POINTS - 1) * 4 * STRIDE)
        .order(ByteOrder.nativeOrder());
    private final BlockPos.MutableBlockPos position = new BlockPos.MutableBlockPos();
    private final float[] ground = new float[MAX_POINTS * MAX_POINTS];
    private final float[] water = new float[ground.length];
    private final int[] surfaceTint = new int[ground.length];
    private final boolean[] sampledTint = new boolean[ground.length];
    private final Map<BlockState, Material> materials = new IdentityHashMap<>();
    private final Random modelRandom = new Random(0);
    private Material waterMaterial;
    private Material trunkMaterial;
    private ClientLevel level;
    private int scanX = Integer.MIN_VALUE;
    private int scanZ;
    private int scanNear;
    private int scanFar;
    private long lastScan;
    private boolean dirty = true;
    private int scanDistance;
    private int scanOffset;

    public void invalidate(int x, int z) {
        Column column = columns.get(ChunkPos.asLong(x, z));
        if (column != null) {
            column.dirty = true;
            dirty = true;
        }
    }

    public void clear() {
        for (Column column : columns.values()) column.release();
        columns.clear();
        visibleWater.clear();
        materials.clear();
        waterMaterial = null;
        trunkMaterial = null;
        scanX = Integer.MIN_VALUE;
        lastScan = 0;
        dirty = true;
        level = null;
    }

    public void draw(ByteBuffer state, double x, double y, double z, int far) {
        int cameraX = (int)Math.floor(x / 16.0);
        int cameraZ = (int)Math.floor(z / 16.0);
        int bytes = columns.size() * Integer.BYTES;
        if (visible.capacity() < bytes) {
            int capacity = Integer.highestOneBit(bytes - 1) * 2;
            visible = ByteBuffer.allocateDirect(capacity).order(ByteOrder.nativeOrder());
            visibleWater = ByteBuffer.allocateDirect(capacity).order(ByteOrder.nativeOrder());
        }
        visible.clear();
        visibleWater.clear();
        int visibleCount = 0;
        Iterator<Long2ObjectMap.Entry<Column>> entries = columns.long2ObjectEntrySet().fastIterator();
        while (entries.hasNext()) {
            Long2ObjectMap.Entry<Column> entry = entries.next();
            Column column = entry.getValue();
            int distance = Math.max(Math.abs(column.x - cameraX), Math.abs(column.z - cameraZ));
            if (distance > far || DirectTerrain.detailedColumns().contains(entry.getLongKey())) continue;
            visible.putInt(column.id);
            if (column.waterId != 0) visibleWater.putInt(column.waterId);
            visibleCount++;
        }
        if (visibleCount != 0) DirectNative.drawDistantTerrain(state, visible, visibleCount, x, y, z);
    }

    public void drawWater(ByteBuffer state, double x, double y, double z) {
        int count = visibleWater.position() / Integer.BYTES;
        if (count != 0) DirectNative.drawDistantTerrain(state, visibleWater, count, x, y, z);
    }

    public void update(double x, double z, int near, int far) {
        ClientLevel world = Minecraft.getInstance().level;
        if (world != level) {
            clear();
            level = world;
        }
        if (level == null || level.dimension() != net.minecraft.world.level.Level.OVERWORLD || far <= near) return;
        int cameraX = (int)Math.floor(x / 16.0);
        int cameraZ = (int)Math.floor(z / 16.0);
        long now = System.nanoTime();
        boolean moved = cameraX != scanX || cameraZ != scanZ || near != scanNear || far != scanFar;
        if (!moved && !dirty && now - lastScan < 350_000_000L) return;
        if (moved || !dirty) {
            scanDistance = Math.max(1, near - 3);
            scanOffset = -scanDistance;
            Iterator<Column> existing = columns.values().iterator();
            while (existing.hasNext()) {
                Column column = existing.next();
                int distance = Math.max(Math.abs(column.x - cameraX), Math.abs(column.z - cameraZ));
                if (distance > far + 3 || distance < near - 4 ||
                    level.getChunkSource().getChunk(column.x, column.z, ChunkStatus.FULL, false) != column.chunk) {
                    column.release();
                    existing.remove();
                }
            }
        }
        scanX = cameraX;
        scanZ = cameraZ;
        scanNear = near;
        scanFar = far;
        lastScan = now;
        dirty = false;
        int built = 0;
        long deadline = now + 650_000L;
        while (scanDistance <= far) {
            int distance = scanDistance, offset = scanOffset++;
            built += updateColumn(cameraX + offset, cameraZ - distance);
            built += updateColumn(cameraX + distance, cameraZ + offset);
            built += updateColumn(cameraX - offset, cameraZ + distance);
            built += updateColumn(cameraX - distance, cameraZ - offset);
            if (scanOffset == scanDistance) scanOffset = -++scanDistance;
            if (scanDistance <= far && (built >= MAX_NEW_COLUMNS || System.nanoTime() > deadline)) {
                dirty = true;
                return;
            }
        }
    }

    private int updateColumn(int x, int z) {
        long key = ChunkPos.asLong(x, z);
        Column column = columns.get(key);
        int distance = Math.max(Math.abs(x - scanX), Math.abs(z - scanZ));
        boolean fine = distance <= scanNear + (column != null && column.fine ? 5 : 3);
        if (column != null && !column.dirty && column.fine == fine) return 0;
        LevelChunk chunk = level.getChunkSource().getChunk(x, z, ChunkStatus.FULL, false);
        if (chunk == null) return 0;
        LevelChunk east = level.getChunkSource().getChunk(x + 1, z, ChunkStatus.FULL, false);
        LevelChunk south = level.getChunkSource().getChunk(x, z + 1, ChunkStatus.FULL, false);
        LevelChunk southeast = level.getChunkSource().getChunk(x + 1, z + 1, ChunkStatus.FULL, false);
        if (east == null || south == null || southeast == null) return 0;
        if (column != null && column.chunk != chunk) {
            column.release();
            column = null;
        }
        if (column == null) {
            column = new Column(x, z, DirectVulkan.id(), chunk);
            columns.put(key, column);
        }
        build(column, east, south, southeast, fine);
        column.fine = fine;
        return 1;
    }

    private int sampleSurface(Column column, LevelChunk east, LevelChunk south, LevelChunk southeast, int step) {
        int worldX = column.x * 16, worldZ = column.z * 16;
        int axis = 16 / step + 1;
        int land = 0;
        for (int row = 0; row < axis; row++) {
            for (int col = 0; col < axis; col++) {
                int localX = col * step, localZ = row * step;
                LevelChunk sample = row == axis - 1
                    ? col == axis - 1 ? southeast : south
                    : col == axis - 1 ? east : column.chunk;
                int y = sample.getHeight(Heightmap.Types.MOTION_BLOCKING, localX, localZ);
                position.set(worldX + localX, y, worldZ + localZ);
                BlockState block = sample.getBlockState(position);
                int index = row * axis + col;
                net.minecraft.world.level.material.FluidState fluid = block.getFluidState();
                boolean wet = fluid.is(FluidTags.WATER);
                if (!wet) land++;
                water[index] = wet ? y + fluid.getOwnHeight() : Float.NaN;
                ground[index] = wet ? oceanFloor(sample, y) + 1 : groundHeight(sample, y, block);
            }
        }
        return land;
    }

    private void build(Column column, LevelChunk east, LevelChunk south, LevelChunk southeast, boolean fine) {
        int worldX = column.x * 16, worldZ = column.z * 16;
        int step = fine ? NEAR_STEP : FAR_STEP;
        int land = sampleSurface(column, east, south, southeast, step);
        if (fine && land == 0) {
            int fineAxis = 16 / NEAR_STEP + 1, coarseAxis = 16 / FAR_STEP + 1;
            for (int z = 0; z < coarseAxis; z++) {
                for (int x = 0; x < coarseAxis; x++) {
                    ground[z * coarseAxis + x] = ground[2 * z * fineAxis + 2 * x];
                    water[z * coarseAxis + x] = water[2 * z * fineAxis + 2 * x];
                }
            }
            step = FAR_STEP;
        }
        int axis = 16 / step + 1;
        Minecraft minecraft = Minecraft.getInstance();
        if (waterMaterial == null) {
            waterMaterial = new Material(minecraft.getBlockRenderer().getBlockModelShaper()
                .getParticleIcon(Blocks.WATER.defaultBlockState()), -1);
            trunkMaterial = new Material(minecraft.getBlockRenderer().getBlockModelShaper()
                .getParticleIcon(Blocks.OAK_LOG.defaultBlockState()), -1);
        }
        if (step == NEAR_STEP) {
            for (int point = 1; point < axis - 1; point += 2) {
                stitch(point, 1);
                stitch((axis - 1) * axis + point, 1);
                stitch(point * axis, axis);
                stitch(point * axis + axis - 1, axis);
            }
        }
        mesh.clear();
        waterMesh.clear();
        Arrays.fill(sampledTint, false);
        float minY = 256, maxY = 0;
        for (int row = 0; row < axis - 1; row++) {
            for (int col = 0; col < axis - 1; col++) {
                int localX = col * step + step / 2, localZ = row * step + step / 2;
                int y = column.chunk.getHeight(Heightmap.Types.MOTION_BLOCKING, localX, localZ);
                position.set(worldX + localX, y, worldZ + localZ);
                BlockState block = column.chunk.getBlockState(position);
                net.minecraft.world.level.material.FluidState fluid = block.getFluidState();
                boolean wet = fluid.is(FluidTags.WATER);
                float surface = y + fluid.getOwnHeight();
                if (wet) {
                    position.setY(oceanFloor(column.chunk, y));
                    block = column.chunk.getBlockState(position);
                } else if (canopy(block)) {
                    y = groundHeight(column.chunk, y, block) - 1;
                    position.setY(y);
                    block = column.chunk.getBlockState(position);
                }
                Material material = materials.computeIfAbsent(block, this::material);
                int color = material.tint < 0 ? -1 :
                    minecraft.getBlockColors().getColor(block, level, position, material.tint);
                int rgba = (color >>> 16 & 255) | (color & 0x00ff00) | ((color & 255) << 16) | 0xff000000;
                int first = row * axis + col;
                float shade = terrainShade(first, axis, step);
                for (int corner = 0; corner < 4; corner++) {
                    boolean right = corner >= 2;
                    boolean bottom = corner == 1 || corner == 2;
                    int index = first + (bottom ? axis : 0) + (right ? 1 : 0);
                    float x = (index % axis) * step, z = (index / axis) * step;
                    int repeat = 0x10000 | (right ? step : 0) | ((bottom ? step : 0) << 8);
                    float height = ground[index];
                    minY = Math.min(minY, height);
                    maxY = Math.max(maxY, height);
                    vertex(x, height, z, shaded(rgba, shade), material, repeat | 0x20000);
                    if (wet) {
                        if (!sampledTint[index]) {
                            position.set(worldX + (int)x, y, worldZ + (int)z);
                            int tint = BiomeColors.getAverageWaterColor(level, position);
                            surfaceTint[index] = (tint >>> 16 & 255) | (tint & 0x00ff00) |
                                ((tint & 255) << 16) | 0xff000000;
                            sampledTint[index] = true;
                        }
                        float heightAtCorner = Float.isNaN(water[index]) ? surface : water[index];
                        maxY = Math.max(maxY, heightAtCorner);
                        putVertex(waterMesh, x, heightAtCorner, z, surfaceTint[index], waterMaterial, repeat);
                    }
                }
            }
        }
        if (land != 0) {
            for (int z = 2; z < 16; z += FOLIAGE_INTERVAL) {
                for (int x = 2; x < 16; x += FOLIAGE_INTERVAL) {
                    int top = column.chunk.getHeight(Heightmap.Types.MOTION_BLOCKING, x, z);
                    position.set(worldX + x, top, worldZ + z);
                    BlockState leaves = column.chunk.getBlockState(position);
                    if (!leaves.is(BlockTags.LEAVES)) continue;
                    Material material = materials.computeIfAbsent(leaves, this::material);
                    int color = minecraft.getBlockColors().getColor(leaves, level, position, 0);
                    int rgba = (color >>> 16 & 255) | (color & 0x00ff00) | ((color & 255) << 16) | 0xff000000;
                    float groundY = groundHeight(column.chunk, top, leaves);
                    float bottom = Math.max(top - 3, groundY);
                    float peak = top + 1;
                    float lowX = x - 1.5f, highX = x + 1.5f, lowZ = z - 1.5f, highZ = z + 1.5f;
                    minY = Math.min(minY, groundY);
                    maxY = Math.max(maxY, peak);
                    foliage(lowX, lowZ, highX, highZ, bottom, peak, rgba, material);
                    foliage(lowX, highZ, highX, lowZ, bottom, peak, rgba, material);
                    foliage(x - 0.45f, z - 0.45f, x + 0.45f, z + 0.45f, groundY, bottom + 0.5f,
                        0xffd7d7d7, trunkMaterial);
                }
            }
        }
        mesh.flip();
        DirectNative.uploadDistantTerrain(column.id, worldX, worldZ, minY, maxY, mesh.slice());
        waterMesh.flip();
        if (waterMesh.hasRemaining()) {
            if (column.waterId == 0) column.waterId = DirectVulkan.id();
            DirectNative.uploadDistantTerrain(column.waterId, worldX, worldZ, minY, maxY, waterMesh.slice());
        } else {
            column.releaseWater();
        }
        column.dirty = false;
    }

    private void stitch(int point, int stride) {
        ground[point] = (ground[point - stride] + ground[point + stride]) * 0.5f;
        if (!Float.isNaN(water[point]) && !Float.isNaN(water[point - stride]) && !Float.isNaN(water[point + stride])) {
            water[point] = (water[point - stride] + water[point + stride]) * 0.5f;
        }
    }

    private static boolean canopy(BlockState block) {
        return block.is(BlockTags.LEAVES) || block.is(BlockTags.LOGS);
    }

    private int oceanFloor(LevelChunk chunk, int y) {
        int first = y;
        while (y > 0) {
            position.setY(y);
            if (chunk.getBlockState(position).getMaterial().blocksMotion()) break;
            y--;
        }
        position.setY(first);
        return y;
    }

    private int groundHeight(LevelChunk chunk, int y, BlockState block) {
        if (!canopy(block)) return Math.max(0, y + 1);
        int first = y;
        try {
            do {
                position.setY(--y);
                block = chunk.getBlockState(position);
            } while (y > Math.max(0, first - 14) &&
                (canopy(block) || (!block.getMaterial().blocksMotion() && block.getFluidState().isEmpty())));
            return Math.max(0, y + 1);
        } finally {
            position.setY(first);
        }
    }

    private void vertex(float x, float y, float z, int color, Material material, int repeat) {
        putVertex(mesh, x, y, z, color, material, repeat);
    }

    private static void putVertex(ByteBuffer target, float x, float y, float z, int color, Material material, int repeat) {
        target.putFloat(x).putFloat(y).putFloat(z).putInt(color).putInt(material.minimum).putInt(material.maximum)
            .putInt(0x00f000f0).putInt(repeat);
    }

    private void foliage(float x0, float z0, float x1, float z1, float bottom, float peak, int rgba, Material material) {
        vertex(x0, bottom, z0, rgba, material, 0x90100);
        vertex(x1, bottom, z1, rgba, material, 0x90101);
        vertex(x1, peak, z1, rgba, material, 0x90001);
        vertex(x0, peak, z0, rgba, material, 0x90000);
    }

    private float terrainShade(int first, int axis, int step) {
        float dx = (ground[first + 1] + ground[first + axis + 1] -
            ground[first] - ground[first + axis]) / (2 * step);
        float dz = (ground[first + axis] + ground[first + axis + 1] -
            ground[first] - ground[first + 1]) / (2 * step);
        float light = (float)((1.0 + 0.30 * dx - 0.25 * dz) / Math.sqrt(1.0 + dx * dx + dz * dz));
        return Math.max(0.59f, Math.min(1.0f, 0.72f + 0.28f * light));
    }

    private static int shaded(int color, float shade) {
        int red = (int)((color & 255) * shade);
        int green = (int)((color >>> 8 & 255) * shade);
        int blue = (int)((color >>> 16 & 255) * shade);
        return 0xff000000 | red | green << 8 | blue << 16;
    }
    private Material material(BlockState block) {
        BakedModel model = Minecraft.getInstance().getBlockRenderer().getBlockModelShaper().getBlockModel(block);
        modelRandom.setSeed(0);
        List<BakedQuad> top = model.getQuads(block, Direction.UP, modelRandom);
        if (!top.isEmpty()) {
            BakedQuad quad = top.get(0);
            return new Material(((QuadTexture) quad).meshnet$sprite(), quad.getTintIndex());
        }
        return new Material(model.getParticleIcon(), block.is(Blocks.GRASS_BLOCK) ? 0 : -1);
    }

    public interface QuadTexture {
        TextureAtlasSprite meshnet$sprite();
    }

    private static final class Material {
        final int minimum;
        final int maximum;
        final int tint;
        Material(TextureAtlasSprite sprite, int tint) {
            float uInset = (sprite.getU1() - sprite.getU0()) * 0.016f;
            float vInset = (sprite.getV1() - sprite.getV0()) * 0.016f;
            minimum = atlas(sprite.getU0() + uInset, sprite.getV0() + vInset);
            maximum = atlas(sprite.getU1() - uInset, sprite.getV1() - vInset);
            this.tint = tint;
        }
        private static int atlas(float u, float v) {
            return Math.round(u * 65535) | (Math.round(v * 65535) << 16);
        }
    }

    private static final class Column {
        final int x;
        final int z;
        final int id;
        final LevelChunk chunk;
        int waterId;
        boolean fine;
        boolean dirty;
        Column(int x, int z, int id, LevelChunk chunk) {
            this.x = x;
            this.z = z;
            this.id = id;
            this.chunk = chunk;
        }

        void release() {
            DirectNative.deleteBuffer(id);
            releaseWater();
        }

        void releaseWater() {
            if (waterId == 0) return;
            DirectNative.deleteBuffer(waterId);
            waterId = 0;
        }
    }
}
