package mcopt.legacy.mixin;
import com.mojang.blaze3d.platform.TextureUtil;
import java.nio.IntBuffer;
import mcopt.legacy.DirectVulkan;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.*;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;
@Mixin(TextureUtil.class)
public abstract class DirectTextureUtilMixin {
    @Inject(method = "initTexture", at = @At("HEAD"), cancellable = true)
    private static void meshnet$texture(IntBuffer pixels, int width, int height, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.image(3553, 0, 6408, width, height, 0, 32993, 33639, pixels);
        DirectVulkan.texParameter(3553, 10241, 9729);
        DirectVulkan.texParameter(3553, 10240, 9728);
        callback.cancel();
    }
}
