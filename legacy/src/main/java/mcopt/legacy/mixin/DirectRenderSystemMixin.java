package mcopt.legacy.mixin;
import com.mojang.blaze3d.systems.RenderSystem;
import mcopt.legacy.DirectVulkan;
import net.minecraft.client.Minecraft;
import org.lwjgl.glfw.GLFW;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.*;
import org.spongepowered.asm.mixin.injection.callback.*;
@Mixin(RenderSystem.class)
public abstract class DirectRenderSystemMixin {
    @Inject(method = "initRenderer", at = @At("HEAD"), cancellable = true)
    private static void meshnet$init(int verbosity, boolean synchronous, CallbackInfo callback) {
        if (DirectVulkan.active()) {
            com.mojang.blaze3d.platform.GlConst.GL_FRAMEBUFFER = 36160;
            com.mojang.blaze3d.platform.GlConst.GL_RENDERBUFFER = 36161;
            com.mojang.blaze3d.platform.GlConst.GL_COLOR_ATTACHMENT0 = 36064;
            com.mojang.blaze3d.platform.GlConst.GL_DEPTH_ATTACHMENT = 36096;
            com.mojang.blaze3d.platform.GlConst.GL_FRAMEBUFFER_COMPLETE = 36053;
            callback.cancel();
        }
    }
    @Inject(method = "maxSupportedTextureSize", at = @At("HEAD"), cancellable = true)
    private static void meshnet$maxTexture(CallbackInfoReturnable<Integer> callback) {
        if (DirectVulkan.active())
            callback.setReturnValue(16384);
    }
    @Redirect(method = "flipFrame",
              at = @At(value = "INVOKE", target = "Lorg/lwjgl/glfw/GLFW;glfwSwapBuffers(J)V"))
    private static void
    meshnet$present(long window) {
        if (DirectVulkan.active()) {
            int[] width = new int[1], height = new int[1];
            GLFW.glfwGetFramebufferSize(window, width, height);
            DirectVulkan.present(width[0], height[0]);
        } else
            GLFW.glfwSwapBuffers(window);
    }
}
