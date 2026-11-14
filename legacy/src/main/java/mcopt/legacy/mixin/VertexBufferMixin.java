package mcopt.legacy.mixin;
import com.mojang.blaze3d.vertex.VertexBuffer;
import mcopt.legacy.DirectBufferAccess;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Shadow;
import org.spongepowered.asm.mixin.Unique;
@Mixin(VertexBuffer.class)
public abstract class VertexBufferMixin implements DirectBufferAccess {
    @Shadow private int id;
    @Shadow private int vertexCount;
    @Unique private volatile int meshnet$layer = -1;
    @Unique private volatile int meshnet$revision;
    @Override
    public int meshnet$bufferId() {
        return id;
    }
    @Override
    public int meshnet$terrainLayer() {
        return meshnet$layer;
    }
    @Override
    public int meshnet$uploadRevision() {
        return meshnet$revision;
    }
    @Override
    public void meshnet$markTerrain(int layer) {
        meshnet$layer = layer;
        meshnet$revision++;
    }
    @Override
    public void meshnet$vertexCount(int count) {
        vertexCount = count;
    }
}
