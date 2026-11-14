package mcopt.legacy.mixin;
import java.util.concurrent.atomic.AtomicReference;
import mcopt.legacy.DirectTerrain;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.*;
@Mixin(targets = "net.minecraft.client.renderer.chunk.ChunkRenderDispatcher$RenderChunk$RebuildTask")
public abstract class DirectChunkCompilationMixin {
    @Redirect(method = "*",
              at = @At(value = "INVOKE",
                       target = "Ljava/util/concurrent/atomic/AtomicReference;set(Ljava/lang/Object;)V"))
    private void
    meshnet$compiled(AtomicReference<Object> reference, Object value) {
        reference.set(value);
        DirectTerrain.published(reference, value);
    }
}
