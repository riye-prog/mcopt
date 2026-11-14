package mcopt.legacy.mixin;
import com.mojang.blaze3d.vertex.BufferUploader;
import com.mojang.blaze3d.vertex.VertexFormat;
import java.nio.ByteBuffer;
import mcopt.legacy.DirectVulkan;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.*;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;
@Mixin(BufferUploader.class)
public abstract class DirectBufferUploaderMixin {
    @Inject(method = "_end", at = @At("HEAD"), cancellable = true)
    private static void meshnet$draw(ByteBuffer data, int mode, VertexFormat format, int vertices,
                                     CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        data.clear();
        DirectVulkan.draw(data, mode, format, vertices);
        callback.cancel();
    }
}
