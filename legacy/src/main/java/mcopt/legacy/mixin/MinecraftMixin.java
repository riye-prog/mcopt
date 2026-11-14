package mcopt.legacy.mixin;
import com.mojang.blaze3d.systems.RenderSystem;
import net.minecraft.util.thread.ReentrantBlockableEventLoop;
import mcopt.legacy.DirectVulkan;
import mcopt.legacy.DirectTerrain;

import mcopt.legacy.LegacySmoke;
import net.minecraft.client.Minecraft;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.Redirect;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(Minecraft.class)
public abstract class MinecraftMixin extends ReentrantBlockableEventLoop<Runnable> {
    protected MinecraftMixin(String name) {
        super(name);
    }

    @Redirect(method = "runTick", at = @At(value = "INVOKE",
            target = "Lnet/minecraft/client/Minecraft;runAllTasks()V"))
    private void meshnet$budgetTasks(Minecraft minecraft) {
        if (!DirectVulkan.active() || !DirectTerrain.FAST || minecraft.level == null || minecraft.player == null
            || minecraft.getOverlay() != null || minecraft.screen != null) {
            runAllTasks();
            return;
        }
        long deadline = System.nanoTime() + 950_000L;
        while (pollTask() && System.nanoTime() < deadline) {
        }
    }

    @Redirect(method = "runTick", at = @At(value = "INVOKE", target = "Ljava/lang/Thread;yield()V"))
    private void meshnet$yield() {
        if (!DirectVulkan.active() || !DirectTerrain.FAST) Thread.yield();
    }

    @Redirect(method = "runTick", at = @At(value = "INVOKE",
            target = "Lcom/mojang/blaze3d/systems/RenderSystem;clear(IZ)V", ordinal = 0))
    private void meshnet$clear(int mask, boolean checkErrors) {
        if (DirectVulkan.active()) ((Minecraft)(Object)this).getMainRenderTarget().bindWrite(true);
        RenderSystem.clear(mask, checkErrors);
    }

    @Inject(method = "runTick", at = @At("RETURN"))
    private void meshnet$smoke(boolean advance, CallbackInfo callback) {
        LegacySmoke.frame((Minecraft)(Object)this);
    }

}
