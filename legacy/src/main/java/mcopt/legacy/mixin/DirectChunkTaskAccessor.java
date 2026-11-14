package mcopt.legacy.mixin;

import java.util.concurrent.atomic.AtomicBoolean;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.gen.Accessor;

@Mixin(targets = "net.minecraft.client.renderer.chunk.ChunkRenderDispatcher$RenderChunk$ChunkCompileTask")
public interface DirectChunkTaskAccessor {
    @Accessor("isCancelled")
    AtomicBoolean meshnet$cancelled();
}
