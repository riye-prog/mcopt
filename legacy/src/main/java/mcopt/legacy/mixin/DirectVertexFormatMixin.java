package mcopt.legacy.mixin;
import com.mojang.blaze3d.vertex.VertexFormat;
import mcopt.legacy.DirectVulkan;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.*;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;
@Mixin(VertexFormat.class)
public abstract class DirectVertexFormatMixin {
    @Inject(method = "setupBufferState", at = @At("HEAD"), cancellable = true)
    private void meshnet$format(long address, CallbackInfo callback) {
        if (DirectVulkan.active()) {
            DirectVulkan.format((VertexFormat)(Object)this);
            callback.cancel();
        }
    }
    @Inject(method = "clearBufferState", at = @At("HEAD"), cancellable = true)
    private void meshnet$clear(CallbackInfo callback) {
        if (DirectVulkan.active())
            callback.cancel();
    }
}
