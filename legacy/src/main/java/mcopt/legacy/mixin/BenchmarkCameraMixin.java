package mcopt.legacy.mixin;

import net.minecraft.client.Minecraft;
import net.minecraft.client.renderer.GameRenderer;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(GameRenderer.class)
public abstract class BenchmarkCameraMixin {
	private static final boolean MESHNET_BENCHMARK = Boolean.getBoolean("meshnet.benchmark") && !System.getProperty("meshnet.benchmarkBackend", "bridge").equals("bridge");

	@Inject(method = "renderLevel", at = @At("HEAD"))
	private void meshnet$fixedCamera(CallbackInfo callback) {
		if (!MESHNET_BENCHMARK) return;
		Minecraft minecraft = Minecraft.getInstance();
		if (minecraft.player == null) return;
		double y = mcopt.legacy.DirectBenchmark.moving() ? 96 : 80;
		double z = 184.5 + mcopt.legacy.DirectBenchmark.travel();
		minecraft.player.setPos(-132.5, y, z);
		minecraft.player.xo = -132.5;
		minecraft.player.yo = y;
		minecraft.player.zo = z;
		minecraft.player.yRot = minecraft.player.yRotO = 0;
		minecraft.player.xRot = minecraft.player.xRotO = 20;
	}
}
