package mcopt.legacy;

import com.mojang.blaze3d.vertex.BufferBuilder;
import com.mojang.blaze3d.vertex.VertexBuffer;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.atomic.AtomicBoolean;

public interface DirectChunkUploadAccess {
    CompletableFuture<Void> meshnet$uploadChunkLayer(BufferBuilder builder, VertexBuffer target, AtomicBoolean cancelled);
}
