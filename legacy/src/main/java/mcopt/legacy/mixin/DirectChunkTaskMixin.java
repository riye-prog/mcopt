package mcopt.legacy.mixin;

import com.mojang.blaze3d.vertex.BufferBuilder;
import com.mojang.blaze3d.vertex.VertexBuffer;
import java.util.concurrent.CompletableFuture;
import mcopt.legacy.DirectChunkUploadAccess;
import net.minecraft.client.renderer.chunk.ChunkRenderDispatcher;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Redirect;

@Mixin(targets = {
    "net.minecraft.client.renderer.chunk.ChunkRenderDispatcher$RenderChunk$RebuildTask",
    "net.minecraft.client.renderer.chunk.ChunkRenderDispatcher$RenderChunk$ResortTransparencyTask"
})
public abstract class DirectChunkTaskMixin {
    @Redirect(method = "*", at = @At(value = "INVOKE", target =
        "Lnet/minecraft/client/renderer/chunk/ChunkRenderDispatcher;uploadChunkLayer(Lcom/mojang/blaze3d/vertex/BufferBuilder;Lcom/mojang/blaze3d/vertex/VertexBuffer;)Ljava/util/concurrent/CompletableFuture;"))
    private CompletableFuture<Void> meshnet$upload(ChunkRenderDispatcher dispatcher, BufferBuilder builder, VertexBuffer target) {
        return ((DirectChunkUploadAccess) dispatcher).meshnet$uploadChunkLayer(builder, target,
            ((DirectChunkTaskAccessor) this).meshnet$cancelled());
    }
}
