package mcopt.legacy.mixin;

import com.mojang.blaze3d.pipeline.RenderTarget;
import mcopt.legacy.DirectNative;
import mcopt.legacy.DirectVulkan;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(RenderTarget.class)
public abstract class DirectRenderTargetMixin {
    @Inject(method = "_blitToScreen", at = @At("HEAD"), cancellable = true)
    private void meshnet$presentTarget(int width, int height, boolean opaque, CallbackInfo callback) {
        if (!DirectVulkan.active() || !opaque) return;
        RenderTarget target = (RenderTarget)(Object)this;
        if (target.width != target.viewWidth || target.height != target.viewHeight) return;
        DirectNative.presentTarget(target.frameBufferId);
        callback.cancel();
    }
}
