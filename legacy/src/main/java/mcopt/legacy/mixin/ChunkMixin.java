package mcopt.legacy.mixin;
import mcopt.legacy.DirectTerrain;
import net.minecraft.client.renderer.chunk.ChunkRenderDispatcher;
import net.minecraft.core.BlockPos;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Unique;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;
@Mixin(ChunkRenderDispatcher.RenderChunk.class)
public abstract class ChunkMixin {
    @Unique
    private int meshnet$lastX = Integer.MIN_VALUE,
                meshnet$lastY = Integer.MIN_VALUE, meshnet$lastZ = Integer.MIN_VALUE;
    @Inject(method = "setOrigin", at = @At("RETURN"))
    private void meshnet$origin(int x, int y, int z, CallbackInfo callback) {
        ChunkRenderDispatcher.RenderChunk chunk = (ChunkRenderDispatcher.RenderChunk)(Object)this;
        BlockPos origin = chunk.getOrigin();
        if (origin.getX() == meshnet$lastX && origin.getY() == meshnet$lastY &&
            origin.getZ() == meshnet$lastZ)
            return;
        meshnet$lastX = origin.getX();
        meshnet$lastY = origin.getY();
        meshnet$lastZ = origin.getZ();
        DirectTerrain.track(chunk);
    }
}
