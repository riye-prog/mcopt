package mcopt.legacy.mixin;

import com.mojang.math.Vector4f;
import mcopt.legacy.DirectVulkan;
import net.minecraft.client.renderer.culling.Frustum;
import org.spongepowered.asm.mixin.Final;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Shadow;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

@Mixin(Frustum.class)
public abstract class VulkanFrustumMixin {
    @Shadow @Final private Vector4f[] frustumData;

    @Inject(method = "cubeInFrustum(FFFFFF)Z", at = @At("HEAD"), cancellable = true)
    private void meshnet$visible(float minX, float minY, float minZ, float maxX, float maxY, float maxZ,
                                 CallbackInfoReturnable<Boolean> callback) {
        if (!DirectVulkan.active()) return;
        for (Vector4f plane : frustumData) {
            float x = plane.x(), y = plane.y(), z = plane.z();
            float distance = x * (x >= 0 ? maxX : minX) + y * (y >= 0 ? maxY : minY)
                + z * (z >= 0 ? maxZ : minZ) + plane.w();
            if (distance <= 0) {
                callback.setReturnValue(false);
                return;
            }
        }
        callback.setReturnValue(true);
    }
}
