package mcopt.legacy.mixin;
import com.mojang.blaze3d.platform.Window;
import mcopt.legacy.LegacyFramePacing;
import mcopt.legacy.LegacyWindowStatus;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Shadow;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.ModifyVariable;
@Mixin(Window.class)
public abstract class WindowMixin implements LegacyWindowStatus {
    @Shadow private boolean vsync;
    @Override
    public boolean meshnet$synchronizedPresentation() {
        return vsync;
    }
    @ModifyVariable(method = "updateVsync", at = @At("HEAD"), argsOnly = true)
    private boolean meshnet$vsync(boolean enabled) {
        return enabled || LegacyFramePacing.SMOOTH;
    }
}
