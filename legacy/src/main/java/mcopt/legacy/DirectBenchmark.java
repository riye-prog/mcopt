package mcopt.legacy;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import com.mojang.blaze3d.platform.NativeImage;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import net.minecraft.client.Minecraft;
import net.minecraft.client.Screenshot;
import net.minecraft.client.gui.screens.PauseScreen;
import net.minecraft.client.gui.screens.TitleScreen;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.level.GameRules;
import org.lwjgl.PointerBuffer;
import org.lwjgl.glfw.GLFW;
import org.lwjgl.opengl.GL11;
public final class DirectBenchmark {
    private static final int[] DISTANCES = {24, 24};
    private static final boolean SHORT = Boolean.getBoolean("meshnet.benchmark.short");
    private static final List<Long> SAMPLES = new ArrayList<>();
    private static final JsonArray PHASES = new JsonArray();
    private static int titleFrames, phase;
    private static long start, loaded, phaseStart, previous;
    private static double presentsAtSampleStart, missedAcquiresAtSampleStart;
    private static double actualPresentsAtSampleStart, lastPresentedAtSampleStart;
    private static boolean finished, validatingEffects;
    private static long effectsStarted;
    private static volatile net.minecraft.world.entity.animal.Pig validationPig;
    private static String backend() { return DirectVulkan.active() ? "vulkan" : "opengl"; }
    public static boolean moving() { return phase > 0; }
    public static double travel() { return moving() ? Math.min(156, (System.nanoTime() - phaseStart) / 1e9 * 12.0) : 0; }
    private static String scenario() { return moving() ? "moving" : "stationary"; }
    private static void positionBenchmarkWindow(long window) {
        PointerBuffer monitors = GLFW.glfwGetMonitors();
        int[] x = new int[1], y = new int[1], width = new int[1], height = new int[1];
        float[] scaleX = new float[1], scaleY = new float[1];
        if (monitors != null) {
            for (int i = monitors.position(); i < monitors.limit(); i++) {
                long monitor = monitors.get(i);
                GLFW.glfwGetMonitorWorkarea(monitor, x, y, width, height);
                GLFW.glfwGetMonitorContentScale(monitor, scaleX, scaleY);
                int windowWidth = Math.round(1600 / scaleX[0]);
                int windowHeight = Math.round(900 / scaleY[0]);
                if (windowWidth > width[0] || windowHeight > height[0])
                    continue;
                GLFW.glfwSetWindowPos(window, x[0] + (width[0] - windowWidth) / 2,
                                      y[0] + (height[0] - windowHeight) / 2);
                GLFW.glfwSetWindowSize(window, windowWidth, windowHeight);
                if (Boolean.getBoolean("meshnet.benchmark.focus")) GLFW.glfwFocusWindow(window);
                return;
            }
        }
        throw new IllegalStateException("no display work area fits the 1600x900 benchmark window");
    }
    public static void frame(Minecraft minecraft) {
        if (finished)
            return;
        long now = System.nanoTime();
        if (validatingEffects) {
            if (now - effectsStarted < 2_000_000_000L)
                return;
            try (NativeImage image = Screenshot.takeScreenshot(1600, 900, minecraft.getMainRenderTarget())) {
                image.writeToFile(Paths.get("direct-effects.png"));
            } catch (java.io.IOException error) {
                throw new IllegalStateException(error);
            }
            finished = true;
            MinecraftServer server = minecraft.getSingleplayerServer();
            server.execute(() -> {
                if (validationPig != null)
                    validationPig.remove();
                minecraft.execute(minecraft::stop);
            });
            return;
        }
        if (start == 0) {
            if (!(minecraft.screen instanceof TitleScreen) || minecraft.getOverlay() != null ||
                ++titleFrames < 30)
                return;
            minecraft.options.enableVsync = false;
            minecraft.options.framerateLimit = 260;
            minecraft.options.pauseOnLostFocus = false;
            minecraft.options.bobView = false;
            minecraft.options.renderDistance = DISTANCES[0];
            minecraft.getWindow().setFramerateLimit(260);
            minecraft.getWindow().updateVsync(false);
            positionBenchmarkWindow(minecraft.getWindow().getWindow());
            start = now;
            minecraft.loadLevel("meshnet-backend-comparison");
            return;
        }
        if (now - start > 150_000_000_000L)
            throw new IllegalStateException("bounded Vulkan benchmark timed out");
        if (minecraft.screen instanceof PauseScreen)
            minecraft.setScreen(null);
        if (minecraft.level == null || minecraft.player == null || minecraft.screen != null)
            return;
        long window = minecraft.getWindow().getWindow();
        if (Boolean.getBoolean("meshnet.benchmark.focus") && GLFW.glfwGetWindowAttrib(window, GLFW.GLFW_FOCUSED) == 0)
            GLFW.glfwFocusWindow(window);
        if (loaded == 0) {
            loaded = phaseStart = now;
            MinecraftServer server = minecraft.getSingleplayerServer();
            server.execute(() -> {
                server.getGameRules().getRule(GameRules.RULE_DAYLIGHT).set(false, server);
                server.getGameRules().getRule(GameRules.RULE_DOMOBSPAWNING).set(false, server);
                server.overworld().setDayTime(6000);
                server.overworld().setWeatherParameters(6000, 0, false, false);
                for (ServerPlayer player : server.getPlayerList().getPlayers()) {
                    player.abilities.flying = true;
                    player.onUpdateAbilities();
                    player.teleportTo(server.overworld(), -132.5, 80, 184.5, 0, 20);
                }
            });
        }
        long warmup = (phase == 0 ? (SHORT ? 12L : 26L) : 3L) * 1_000_000_000L;
        if (now - phaseStart < warmup) {
            previous = now;
            return;
        }
        if (SAMPLES.isEmpty() && DirectVulkan.active()) {
            double[] stats = DirectNative.frameStats();
            presentsAtSampleStart = stats[6];
            missedAcquiresAtSampleStart = stats[7];
            actualPresentsAtSampleStart = stats[8];
            lastPresentedAtSampleStart = stats[9];
        }
        if (previous != 0)
            SAMPLES.add(now - previous);
        if (DirectVulkan.active() && (SAMPLES.size() & 15) == 0) DirectNative.frameStats();
        previous = now;
        if (now - phaseStart < warmup + (SHORT ? 6_000_000_000L : 10_000_000_000L))
            return;
        long[] values = new long[SAMPLES.size()];
        if (values.length == 0) throw new IllegalStateException("Vulkan benchmark had no frame samples");
        double total = 0;
        for (int i = 0; i < values.length; i++)
            total += values[i] = SAMPLES.get(i);
        Arrays.sort(values);
        JsonObject result = new JsonObject();
        result.addProperty("render_distance", DISTANCES[phase]);
        result.addProperty("scenario", scenario());
        result.addProperty("terrain_distance", DirectTerrain.detailDistance(DISTANCES[phase]));
        result.addProperty("samples", values.length);
        result.addProperty("fps", values.length * 1_000_000_000.0 / total);
        result.addProperty("p50_ms", percentile(values, .5));
        result.addProperty("p95_ms", percentile(values, .95));
        result.addProperty("p99_ms", percentile(values, .99));
        result.addProperty("p99_9_ms", percentile(values, .999));
        result.addProperty("max_ms", percentile(values, 1));
        result.addProperty("frames_within_180fps_budget_percent",
            100.0 * Arrays.stream(values).filter(value -> value <= 1_000_000_000L / 180).count() / values.length);
        result.addProperty("chunks", minecraft.levelRenderer.getChunkStatistics());
        result.addProperty("terrain_draws", DirectTerrain.frames());
        if (DirectVulkan.active()) {
            double[] stats = DirectNative.frameStats();

            result.addProperty("last_fence_wait_ms", stats[1]);

            result.addProperty("source_terrain_vertices", stats[0]);
            result.addProperty("merged_terrain_vertices", stats[2]);
            result.addProperty("native_chunk_sections", stats[3]);
            result.addProperty("native_chunk_commands", stats[4]);
            result.addProperty("terrain_pages", stats[5]);
            result.addProperty("present_submissions_per_second", (stats[6] - presentsAtSampleStart)
                * 1_000_000_000.0 / Math.max(1, total - SAMPLES.get(0)));
            result.addProperty("missed_image_acquires", stats[7] - missedAcquiresAtSampleStart);
            if (lastPresentedAtSampleStart > 0 && stats[9] > lastPresentedAtSampleStart) {
                result.addProperty("display_presentations_per_second",
                    (stats[8] - actualPresentsAtSampleStart) * 1_000_000_000.0 / (stats[9] - lastPresentedAtSampleStart));
            }
        }
        PHASES.add(result);
        System.out.println("meshnet: direct benchmark " + backend() + " " + result);
        try (NativeImage image = Screenshot.takeScreenshot(1600, 900, minecraft.getMainRenderTarget())) {
            image.writeToFile(Paths.get("direct-" + backend() + "-" + scenario() + ".png"));
        } catch (java.io.IOException error) {
            throw new IllegalStateException(error);
        }
        phase++;
        if (phase < DISTANCES.length) {
            minecraft.options.renderDistance = DISTANCES[phase];
            phaseStart = System.nanoTime();
            previous = 0;
            SAMPLES.clear();
            return;
        }
        JsonObject report = new JsonObject();
        report.addProperty("backend", backend());
        report.addProperty("renderer", DirectVulkan.active() ? DirectVulkan.renderer()
                                                            : GL11.glGetString(GL11.GL_RENDERER));
        report.addProperty("width", minecraft.getWindow().getWidth());
        report.addProperty("height", minecraft.getWindow().getHeight());
        report.addProperty("render_width", minecraft.getMainRenderTarget().width);
        report.addProperty("render_height", minecraft.getMainRenderTarget().height);
        report.addProperty("focused", GLFW.glfwGetWindowAttrib(minecraft.getWindow().getWindow(), GLFW.GLFW_FOCUSED) != 0);
        report.addProperty("display_refresh_hz", GLFW.glfwGetVideoMode(GLFW.glfwGetPrimaryMonitor()).refreshRate());
        report.addProperty("vsync", false);
        report.addProperty("camera", "-132.5,80,184.5 yaw=0 pitch=20");
        report.add("phases", PHASES);
        try {
            Files.write(Paths.get("direct-" + backend() + ".json"),
                        new GsonBuilder().setPrettyPrinting().create().toJson(report).getBytes(
                            StandardCharsets.UTF_8));
        } catch (java.io.IOException error) {
            throw new IllegalStateException(error);
        }
        if (DirectVulkan.active()) {
            validatingEffects = true;
            effectsStarted = System.nanoTime();
            MinecraftServer server = minecraft.getSingleplayerServer();
            server.execute(() -> {
                net.minecraft.world.entity.animal.Pig pig = new net.minecraft.world.entity.animal.Pig(
                    net.minecraft.world.entity.EntityType.PIG, server.overworld());
                validationPig = pig;
                pig.setPos(-132.5, 76, 194.5);
                pig.setNoAi(true);
                pig.setNoGravity(true);
                pig.setGlowing(true);
                server.overworld().addFreshEntity(pig);
            });
        } else {
            finished = true;
            minecraft.stop();
        }
    }
    private static double percentile(long[] values, double q) {
        return values.length == 0
            ? 0
            : values[Math.min(values.length - 1, Math.max(0, (int)Math.ceil(values.length * q) - 1))] /
                  1_000_000.0;
    }
}
