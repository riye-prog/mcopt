package mcopt.legacy;

import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Locale;
import java.util.Properties;
import net.fabricmc.loader.api.FabricLoader;
import net.fabricmc.loader.api.entrypoint.PreLaunchEntrypoint;

public final class LegacyVulkanBackend implements PreLaunchEntrypoint {
    private static final boolean REQUESTED = readPreference();
    private static boolean configured;
    public static boolean requested() { return REQUESTED; }
    public static boolean configured() { return configured; }
    private static boolean readPreference() {
        String override = System.getProperty("meshnet.nativeVulkan");
        if (override != null)
            return Boolean.parseBoolean(override);
        if (!System.getProperty("os.name", "").toLowerCase(Locale.ROOT).contains("mac"))
            return false;
        Path path = FabricLoader.getInstance().getGameDir().resolve("config/meshnet/direct-vulkan.properties");
        if (!Files.exists(path))
            return true;
        try (InputStream input = Files.newInputStream(path)) {
            Properties settings = new Properties();
            settings.load(input);
            return Boolean.parseBoolean(settings.getProperty("enabled", "true"));
        } catch (IOException exception) {
            throw new IllegalStateException("could not read direct Vulkan settings", exception);
        }
    }
    public static void verifyContext() {
        if (REQUESTED && (!DirectVulkan.ready() || org.lwjgl.glfw.GLFW.glfwGetCurrentContext() != 0))
            throw new IllegalStateException("direct Vulkan initialization failed");
    }
    @Override
    public void onPreLaunch() {
        if (!REQUESTED)
            return;
        if (!System.getProperty("os.name", "").toLowerCase(Locale.ROOT).contains("mac"))
            throw new IllegalStateException("direct Vulkan requires macOS");
        if (FabricLoader.getInstance().isModLoaded("sodium") ||
            FabricLoader.getInstance().isModLoaded("sodiummac") ||
            FabricLoader.getInstance().isModLoaded("meshnet-opengl"))
            throw new IllegalStateException(
                "Meshnet direct Vulkan replaces the terrain renderer; remove Sodium and Meshnet OpenGL from this instance");
        if (!"aarch64".equals(System.getProperty("os.arch")) && !"arm64".equals(System.getProperty("os.arch")))
            throw new IllegalStateException("direct Vulkan requires an Apple Silicon Java runtime");
        if (!LegacyNative.available())
            throw new IllegalStateException("direct Vulkan native library is unavailable");
        System.setProperty("meshnet.legacyMetal", "false");
        configured = true;
    }
}
