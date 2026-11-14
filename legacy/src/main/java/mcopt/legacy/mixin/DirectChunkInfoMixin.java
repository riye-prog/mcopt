package mcopt.legacy.mixin;
import mcopt.legacy.DirectChunkInfoAccess;
import net.minecraft.client.renderer.chunk.ChunkRenderDispatcher;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.gen.Accessor;
@Mixin(targets = "net.minecraft.client.renderer.LevelRenderer$RenderChunkInfo")
public interface DirectChunkInfoMixin extends DirectChunkInfoAccess {
    @Accessor("chunk") ChunkRenderDispatcher.RenderChunk meshnet$chunk();
}
