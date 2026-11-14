package mcopt.legacy;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonObject;
import com.mojang.blaze3d.platform.NativeImage;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.Arrays;
import net.minecraft.client.Minecraft;
import net.minecraft.client.Screenshot;
import net.minecraft.client.gui.screens.PauseScreen;
import net.minecraft.client.gui.screens.TitleScreen;
import net.minecraft.core.RegistryAccess;
import net.minecraft.world.Difficulty;
import net.minecraft.world.level.DataPackConfig;
import net.minecraft.world.level.GameRules;
import net.minecraft.world.level.GameType;
import net.minecraft.world.level.LevelSettings;
import net.minecraft.world.level.dimension.DimensionType;
import net.minecraft.world.level.levelgen.FlatLevelSource;
import net.minecraft.world.level.levelgen.WorldGenSettings;
import net.minecraft.world.level.levelgen.flat.FlatLevelGeneratorSettings;
import org.lwjgl.glfw.GLFW;
public final class LegacySmoke {
    private static final boolean ENABLED = Boolean.getBoolean("meshnet.smoke");
    private static final long[] FRAMES = new long[Integer.getInteger("meshnet.smokeSamples", 120)];
    private static long started, loaded, previous;
    private static int titleFrames, samples;
    private static boolean finished;
    public static void frame(Minecraft minecraft) {
        if (Boolean.getBoolean("meshnet.directBenchmark")) {
            DirectBenchmark.frame(minecraft);
            return;
        }
        if (!ENABLED || finished)
            return;
        long now = System.nanoTime();
        if (started == 0) {
            if (!(minecraft.screen instanceof TitleScreen) || minecraft.getOverlay() != null ||
                ++titleFrames < 30)
                return;
            minecraft.options.renderDistance = 4;
            minecraft.options.pauseOnLostFocus = false;
            started = now;
            LevelSettings settings =
                new LevelSettings("meshnet smoke", GameType.CREATIVE, false, Difficulty.PEACEFUL, true,
                                  new GameRules(), DataPackConfig.DEFAULT);
            WorldGenSettings generation = new WorldGenSettings(
                1161L, false, false,
                WorldGenSettings.withOverworld(DimensionType.defaultDimensions(1161L),
                                               new FlatLevelSource(FlatLevelGeneratorSettings.getDefault())));
            minecraft.createLevel("meshnet-smoke-" + System.currentTimeMillis(), settings,
                                  RegistryAccess.builtin(), generation);
            return;
        }
        if (now - started > 90_000_000_000L)
            throw new IllegalStateException("Vulkan smoke check timed out");
        if (minecraft.screen instanceof PauseScreen)
            minecraft.setScreen(null);
        if (minecraft.level == null || minecraft.player == null || minecraft.screen != null)
            return;
        if (loaded == 0)
            loaded = now;
        if (now - loaded < 3_000_000_000L) {
            previous = now;
            return;
        }
        FRAMES[samples++] = now - previous;
        previous = now;
        if (samples < FRAMES.length)
            return;
        Arrays.sort(FRAMES);
        JsonObject report = new JsonObject();
        report.addProperty("backend", DirectVulkan.active() ? "direct-vulkan" : "opengl");
        report.addProperty("native_initialized", DirectVulkan.ready());
        report.addProperty("opengl_context", GLFW.glfwGetCurrentContext());
        report.addProperty("terrain_draws", DirectTerrain.frames());
        report.addProperty("samples", samples);
        report.addProperty("p50_ms", FRAMES[samples / 2] / 1_000_000.0);
        report.addProperty("p99_ms", FRAMES[Math.min(samples - 1, (int)(samples * .99))] / 1_000_000.0);
        if (DirectVulkan.active() &&
            (!DirectVulkan.ready() || GLFW.glfwGetCurrentContext() != 0 || DirectTerrain.frames() == 0))
            throw new IllegalStateException("direct Vulkan renderer did not render without OpenGL");
        try (NativeImage image = Screenshot.takeScreenshot(minecraft.getWindow().getWidth(),
                                                           minecraft.getWindow().getHeight(),
                                                           minecraft.getMainRenderTarget())) {
            image.writeToFile(Paths.get("meshnet-world.png"));
            Files.write(Paths.get("meshnet-startup.json"),
                        new GsonBuilder().setPrettyPrinting().create().toJson(report).getBytes(
                            StandardCharsets.UTF_8));
        } catch (java.io.IOException error) {
            throw new IllegalStateException(error);
        }
        System.out.println("meshnet: direct renderer validation " + report);
        finished = true;
        minecraft.stop();
    }
}
