package mcopt.legacy.mixin;

import com.mojang.blaze3d.systems.RenderSystem;
import com.mojang.blaze3d.vertex.BufferBuilder;
import com.mojang.blaze3d.vertex.VertexBuffer;
import java.nio.ByteBuffer;
import java.util.Queue;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.atomic.AtomicBoolean;
import mcopt.legacy.DirectBufferAccess;
import mcopt.legacy.DirectChunkUploadAccess;
import mcopt.legacy.DirectNative;
import mcopt.legacy.DirectVulkan;
import net.minecraft.client.renderer.chunk.ChunkRenderDispatcher;
import org.spongepowered.asm.mixin.Final;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Shadow;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

@Mixin(ChunkRenderDispatcher.class)
public abstract class VulkanChunkUploadMixin implements DirectChunkUploadAccess {
    @Shadow @Final private Queue<Runnable> toUpload;
    @Shadow public abstract CompletableFuture<Void> uploadChunkLayer(BufferBuilder builder, VertexBuffer target);

    @Override
    public CompletableFuture<Void> meshnet$uploadChunkLayer(BufferBuilder builder, VertexBuffer target, AtomicBoolean cancelled) {
        if (!DirectVulkan.active()) return uploadChunkLayer(builder, target);
        DirectBufferAccess buffer = (DirectBufferAccess) target;
        int layer = buffer.meshnet$terrainLayer();
        if (layer < 0) return uploadChunkLayer(builder, target);
        int revision = buffer.meshnet$uploadRevision();
        ByteBuffer vertices = builder.popNextBuffer().getSecond().slice();
        if (cancelled.get()) return CompletableFuture.completedFuture(null);
        int[] geometry = layer >= 3 ? null : DirectNative.prepareTerrain(vertices, DirectVulkan.GREEDY_TERRAIN);
        Runnable upload = () -> {
            int id = buffer.meshnet$bufferId();
            if (id < 0 || cancelled.get() || revision != buffer.meshnet$uploadRevision()) return;
            if (geometry == null) DirectNative.uploadBuffer(id, vertices);
            else DirectNative.uploadPreparedTerrain(id, vertices, geometry);
            buffer.meshnet$vertexCount(geometry == null ? vertices.remaining() / 32 : geometry[0]);
        };
        if (RenderSystem.isOnRenderThread()) {
            upload.run();
            return CompletableFuture.completedFuture(null);
        }
        return CompletableFuture.runAsync(upload, toUpload::add);
    }

    @Inject(method = "uploadAllPendingUploads", at = @At("HEAD"), cancellable = true)
    private void meshnet$budgetUploads(CallbackInfoReturnable<Boolean> callback) {
        if (!DirectVulkan.active()) return;
        long deadline = System.nanoTime() + 1_700_000L;
        boolean uploaded = false;
        Runnable work;
        while ((work = toUpload.poll()) != null) {
            work.run();
            uploaded = true;
            if (System.nanoTime() >= deadline) break;
        }
        callback.setReturnValue(uploaded);
    }
}
