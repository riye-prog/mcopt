package mcopt.legacy.mixin;
import com.mojang.blaze3d.platform.Window;
import mcopt.legacy.DirectVulkan;
import org.lwjgl.glfw.GLFW;
import org.lwjgl.glfw.GLFWImage;
import org.lwjgl.opengl.GL;
import org.lwjgl.opengl.GLCapabilities;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.*;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;
@Mixin(Window.class)
public abstract class DirectWindowMixin {
    @Redirect(method = "setIcon",
              at = @At(value = "INVOKE",
                       target = "Lorg/lwjgl/glfw/GLFW;glfwSetWindowIcon(JLorg/lwjgl/glfw/GLFWImage$Buffer;)V"))
    private void meshnet$setIcon(long window, GLFWImage.Buffer icons) {
        if (!DirectVulkan.active())
            GLFW.glfwSetWindowIcon(window, icons);
    }

    @Inject(method = "<init>",
            at = @At(value = "INVOKE",
                     target = "Lorg/lwjgl/glfw/GLFW;glfwCreateWindow(IILjava/lang/CharSequence;JJ)J"))
    private void
    meshnet$noApi(CallbackInfo callback) {
        if (Boolean.getBoolean("meshnet.benchmark") || Boolean.getBoolean("meshnet.smoke")) {
            GLFW.glfwWindowHint(GLFW.GLFW_FOCUSED, GLFW.GLFW_FALSE);
            GLFW.glfwWindowHint(GLFW.GLFW_FOCUS_ON_SHOW, GLFW.GLFW_FALSE);
        }

        if (DirectVulkan.active())
            GLFW.glfwWindowHint(GLFW.GLFW_CLIENT_API, GLFW.GLFW_NO_API);
    }
    @Redirect(method = "<init>",
              at = @At(value = "INVOKE", target = "Lorg/lwjgl/glfw/GLFW;glfwMakeContextCurrent(J)V"))
    private void
    meshnet$context(long window) {
        if (DirectVulkan.active())
            DirectVulkan.initialize(window);
        else
            GLFW.glfwMakeContextCurrent(window);
    }
    @Redirect(method = "<init>",
              at = @At(value = "INVOKE",
                       target = "Lorg/lwjgl/opengl/GL;createCapabilities()Lorg/lwjgl/opengl/GLCapabilities;"))
    private GLCapabilities
    meshnet$capabilities() {
        return DirectVulkan.active() ? null : GL.createCapabilities();
    }
    @Redirect(method = "updateVsync",
              at = @At(value = "INVOKE", target = "Lorg/lwjgl/glfw/GLFW;glfwSwapInterval(I)V"))
    private void
    meshnet$vsync(int interval) {
        if (DirectVulkan.active())
            DirectVulkan.vsync(interval != 0);
        else
            GLFW.glfwSwapInterval(interval);
    }
    @Inject(method = "<init>", at = @At("RETURN"))
    private void meshnet$verify(CallbackInfo callback) {
        mcopt.legacy.LegacyVulkanBackend.verifyContext();
    }
    @Inject(method = "close", at = @At("HEAD"))
    private void meshnet$closeVulkan(CallbackInfo callback) {
        DirectVulkan.close();
    }
}
