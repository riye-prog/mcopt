package mcopt.legacy.mixin;
import com.mojang.blaze3d.shaders.Program;
import java.io.InputStream;
import mcopt.legacy.DirectVulkan;
import mcopt.legacy.DirectPrograms;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.*;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;
@Mixin(Program.class)
public abstract class DirectProgramMixin {
    @Inject(method = "compileShader", at = @At("HEAD"))
    private static void meshnet$program(Program.Type type, String name, InputStream source,
                                        CallbackInfoReturnable<Program> callback) {
        if (DirectVulkan.active())
            DirectPrograms.shaderName(name, type.getExtension());
    }
}
