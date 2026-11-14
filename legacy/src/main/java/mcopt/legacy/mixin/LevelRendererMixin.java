package mcopt.legacy.mixin;
import com.mojang.blaze3d.vertex.PoseStack;
import it.unimi.dsi.fastutil.objects.ObjectList;
import mcopt.legacy.DirectVulkan;
import mcopt.legacy.DirectTerrain;
import mcopt.legacy.DirectChunkInfoAccess;
import net.minecraft.client.Options;
import net.minecraft.client.renderer.chunk.ChunkRenderDispatcher;
import net.minecraft.client.renderer.LevelRenderer;
import net.minecraft.client.renderer.RenderType;
import org.spongepowered.asm.mixin.Final;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Shadow;
import org.spongepowered.asm.mixin.injection.Redirect;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;
@Mixin(LevelRenderer.class)
public abstract class LevelRendererMixin {
    @Shadow @Final private ObjectList<?> renderChunks;
    @Shadow private ChunkRenderDispatcher chunkRenderDispatcher;
    @Shadow private double xTransparentOld;
    @Shadow private double yTransparentOld;
    @Shadow private double zTransparentOld;

    @Redirect(method = {"allChanged", "setupRender"}, at = @At(value = "FIELD",
            target = "Lnet/minecraft/client/Options;renderDistance:I"))
    private int meshnet$detailDistance(Options options) {
        return DirectVulkan.active() ? DirectTerrain.detailDistance(options.renderDistance) : options.renderDistance;
    }
    @Redirect(method = "setupRender", at = @At(value = "INVOKE",
            target = "Lnet/minecraft/client/renderer/chunk/ChunkRenderDispatcher;rebuildChunkSync(Lnet/minecraft/client/renderer/chunk/ChunkRenderDispatcher$RenderChunk;)V"))
    private void meshnet$compileNearby(ChunkRenderDispatcher dispatcher, ChunkRenderDispatcher.RenderChunk chunk) {
        if (DirectVulkan.active() && DirectTerrain.FAST && !chunk.isDirtyFromPlayer())
            chunk.rebuildChunkAsync(dispatcher);
        else dispatcher.rebuildChunkSync(chunk);
    }
    @Inject(method = "setupRender", at = @At("RETURN"))
    private void meshnet$visibility(CallbackInfo callback) {
        DirectTerrain.visible(renderChunks);
    }
    @Inject(method = {"allChanged", "setLevel"}, at = @At("HEAD"))
    private void meshnet$rebuild(CallbackInfo callback) {
        DirectTerrain.clear();
    }
    @Inject(method = "setSectionDirty(IIIZ)V", at = @At("HEAD"))
    private void meshnet$invalidateDistant(int x, int y, int z, boolean playerChanged, CallbackInfo callback) {
        if (DirectVulkan.active() && playerChanged) DirectTerrain.invalidateDistant(x, z);
    }
    @Inject(method = "setBlockDirty(Lnet/minecraft/core/BlockPos;Lnet/minecraft/world/level/block/state/BlockState;Lnet/minecraft/world/level/block/state/BlockState;)V",
            at = @At("HEAD"))
    private void meshnet$invalidateChangedBlock(net.minecraft.core.BlockPos position,
            net.minecraft.world.level.block.state.BlockState previous,
            net.minecraft.world.level.block.state.BlockState current, CallbackInfo callback) {
        if (!DirectVulkan.active()) return;
        int x = position.getX() >> 4, z = position.getZ() >> 4;
        DirectTerrain.invalidateDistant(x, z);
        if ((position.getX() & 15) == 0) DirectTerrain.invalidateDistant(x - 1, z);
        if ((position.getZ() & 15) == 0) DirectTerrain.invalidateDistant(x, z - 1);
        if ((position.getX() & 15) == 0 && (position.getZ() & 15) == 0)
            DirectTerrain.invalidateDistant(x - 1, z - 1);
    }
    @Inject(method = "renderChunkLayer", at = @At("HEAD"), cancellable = true)
    private void meshnet$terrain(RenderType layer, PoseStack pose, double x, double y, double z,
                                 CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        if (layer == RenderType.translucent()) meshnet$sortWater(layer, x, y, z);
        layer.setupRenderState();
        try {
            DirectTerrain.render(layer, pose.last().pose(), x, y, z);
        } finally {
            layer.clearRenderState();
        }
        callback.cancel();
    }

    private void meshnet$sortWater(RenderType layer, double x, double y, double z) {
        double dx = x - xTransparentOld;
        double dy = y - yTransparentOld;
        double dz = z - zTransparentOld;
        if (dx * dx + dy * dy + dz * dz <= 1.0) return;
        xTransparentOld = x;
        yTransparentOld = y;
        zTransparentOld = z;
        int remaining = DirectTerrain.FAST ? 6 : 15;
        for (Object entry : renderChunks) {
            ChunkRenderDispatcher.RenderChunk chunk = ((DirectChunkInfoAccess) entry).meshnet$chunk();
            if (chunk.resortTransparency(layer, chunkRenderDispatcher) && --remaining == 0) break;
        }
    }
}
