package mcopt.legacy.mixin;

import com.mojang.blaze3d.systems.RenderSystem;
import mcopt.legacy.LegacyFramePacing;
import org.lwjgl.glfw.GLFW;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Shadow;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(RenderSystem.class)
public abstract class RenderSystemMixin {
	@Shadow
	private static double lastDrawTime;

	@Inject(method = "limitDisplayFPS", at = @At("HEAD"), cancellable = true)
	private static void meshnet$limit(int framesPerSecond, CallbackInfo callback) {
		if (!LegacyFramePacing.PRECISE) return;
		LegacyFramePacing.limit(framesPerSecond);
		lastDrawTime = GLFW.glfwGetTime();
		callback.cancel();
	}
}
