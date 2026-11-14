package mcopt.legacy.mixin;
import com.mojang.blaze3d.platform.GLX;
import mcopt.legacy.DirectVulkan;
import org.lwjgl.opengl.GL11;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.*;
import org.spongepowered.asm.mixin.injection.callback.*;
@Mixin(GLX.class)
public abstract class DirectGLXMixin {
    @Inject(method = "_setupNvFogDistance", at = @At("HEAD"), cancellable = true)
    private static void meshnet$fog(CallbackInfo callback) {
        if (DirectVulkan.active())
            callback.cancel();
    }
    @Inject(method = {"getOpenGLVersionString", "_getCapsString"}, at = @At("HEAD"), cancellable = true)
    private static void meshnet$description(CallbackInfoReturnable<String> callback) {
        if (DirectVulkan.active())
            callback.setReturnValue(DirectVulkan.renderer());
    }
    @Redirect(method = "_renderCrosshair",
              at = @At(value = "INVOKE", target = "Lorg/lwjgl/opengl/GL11;glLineWidth(F)V"))
    private static void
    meshnet$lineWidth(float width) {
        if (!DirectVulkan.active())
            GL11.glLineWidth(width);
    }
}
