package mcopt.legacy;
import net.fabricmc.api.ClientModInitializer;
public final class LegacyClient implements ClientModInitializer {
    @Override
    public void onInitializeClient() {
        System.out.println(
            "meshnet: Minecraft 1.16.1; backend=" + (DirectVulkan.active() ? "direct Vulkan" : "OpenGL") +
            "; precise limiter=" + LegacyFramePacing.PRECISE);
    }
}
