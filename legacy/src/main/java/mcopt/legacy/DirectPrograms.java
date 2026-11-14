package mcopt.legacy;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.FloatBuffer;
import java.nio.IntBuffer;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.HashMap;
import java.util.Map;
public final class DirectPrograms {
    private static JsonObject manifest;
    private static String pendingName;
    private static int current;
    private static final Map<Integer, Shader> SHADERS = new HashMap<>();
    private static final Map<Integer, Program> PROGRAMS = new HashMap<>();
    private static final Map<Integer, Location> LOCATIONS = new HashMap<>();
    private static final class Shader {
        int type;
        String name, source, error;
        boolean compiled;
    }
    private static final class Program {
        Shader vertex, fragment;
        JsonObject metadata;
        ByteBuffer data;
        int[] units;
        String error;
        boolean linked;
        Map<String, Integer> locations = new HashMap<>();
    }
    private static final class Location {
        Program program;
        int offset, count, sampler = -1;
    }
    private static byte[] resourceBytes(String name) {
        try (InputStream input = DirectPrograms.class.getResourceAsStream("/mcopt/legacy/effects/" + name)) {
            if (input == null)
                throw new IllegalStateException("missing Vulkan effect resource " + name);
            ByteArrayOutputStream output = new ByteArrayOutputStream();
            byte[] bytes = new byte[8192];
            for (int count; (count = input.read(bytes)) >= 0;)
                output.write(bytes, 0, count);
            return output.toByteArray();
        } catch (java.io.IOException error) {
            throw new IllegalStateException(error);
        }
    }
    private static void load() {
        if (manifest == null)
            manifest = new JsonParser().parse(new String(resourceBytes("effects.json"), StandardCharsets.UTF_8)).getAsJsonObject();
    }
    public static void shaderName(String name, String extension) { pendingName = name + extension; }
    public static int createShader(int type) {
        load();
        Shader shader = new Shader();
        shader.type = type;
        shader.name = pendingName;
        int id = DirectVulkan.id();
        SHADERS.put(id, shader);
        return id;
    }
    public static void source(int id, CharSequence source) { SHADERS.get(id).source = source.toString(); }
    public static void compile(int id) {
        Shader shader = SHADERS.get(id);
        JsonElement expected = manifest.getAsJsonObject("shaders").get(shader.name);
        try {
            byte[] bytes =
                MessageDigest.getInstance("SHA-256").digest(shader.source.getBytes(StandardCharsets.UTF_8));
            StringBuilder hex = new StringBuilder();
            for (byte value : bytes)
                hex.append(String.format("%02x", value & 255));
            shader.compiled = expected != null && expected.getAsString().equals(hex.toString());
            shader.error = shader.compiled ? "" : "unsupported modified shader " + shader.name;
        } catch (java.security.NoSuchAlgorithmException error) {
            throw new IllegalStateException(error);
        }
    }
    public static int shaderStatus(int id, int query) {
        Shader shader = SHADERS.get(id);
        return shader != null && shader.compiled ? 1 : 0;
    }
    public static void deleteShader(int id) { SHADERS.remove(id); }
    public static int createProgram() {
        int id = DirectVulkan.id();
        PROGRAMS.put(id, new Program());
        return id;
    }
    public static void attach(int id, int shaderId) {
        Program program = PROGRAMS.get(id);
        Shader shader = SHADERS.get(shaderId);
        if (shader.type == 35633)
            program.vertex = shader;
        else
            program.fragment = shader;
    }
    public static void link(int id) {
        Program program = PROGRAMS.get(id);
        if (program.vertex == null || program.fragment == null || !program.vertex.compiled ||
            !program.fragment.compiled) {
            program.error = "uncompiled Vulkan effect stage";
            return;
        }
        String key =
            program.vertex.name.replace(".vsh", "") + "__" + program.fragment.name.replace(".fsh", "");
        JsonElement metadata = manifest.getAsJsonObject("programs").get(key);
        if (metadata == null) {
            program.error = "unsupported Vulkan shader pair " + key;
            return;
        }
        program.metadata = metadata.getAsJsonObject();
        program.data = ByteBuffer.allocateDirect(Math.max(16, program.metadata.get("size").getAsInt()))
                           .order(ByteOrder.nativeOrder());
        program.units = new int[program.metadata.getAsJsonArray("textures").size()];
        DirectNative.effect(id, resourceBytes(key + ".vert.spv"), resourceBytes(key + ".frag.spv"));
        program.linked = true;
    }
    public static void deleteProgram(int id) {
        Program program = PROGRAMS.remove(id);
        if (program != null) {
            for (int location : program.locations.values())
                LOCATIONS.remove(location);
            DirectNative.deleteEffect(id);
        }
        if (current == id)
            current = 0;
    }
    public static int programStatus(int id, int query) {
        Program program = PROGRAMS.get(id);
        return program != null && program.linked ? 1 : 0;
    }
    public static void use(int id) { current = id; }
    public static int current() { return current; }
    public static void prepare() {
        if (current == 0)
            return;
        Program program = PROGRAMS.get(current);
        if (program == null || !program.linked)
            throw new IllegalStateException("unlinked Vulkan effect");
        DirectNative.effectData(current, program.data, program.units);
    }
    public static int uniform(int id, CharSequence nameValue) {
        Program program = PROGRAMS.get(id);
        String name = nameValue.toString();
        Integer known = program.locations.get(name);
        if (known != null)
            return known;
        Location location = new Location();
        location.program = program;
        JsonElement field = program.metadata.getAsJsonObject("fields").get(name);
        if (field != null) {
            location.offset = field.getAsJsonObject().get("offset").getAsInt();
            location.count = field.getAsJsonObject().get("count").getAsInt();
        } else {
            for (JsonElement texture : program.metadata.getAsJsonArray("textures")) {
                JsonObject entry = texture.getAsJsonObject();
                if (entry.get("name").getAsString().equals(name))
                    location.sampler = entry.get("index").getAsInt();
            }
            if (location.sampler < 0)
                return -1;
        }
        int value = DirectVulkan.id();
        LOCATIONS.put(value, location);
        program.locations.put(name, value);
        return value;
    }
    public static String error(int id) {
        Shader shader = SHADERS.get(id);
        if (shader != null)
            return shader.error == null ? "" : shader.error;
        Program program = PROGRAMS.get(id);
        return program == null || program.error == null ? "" : program.error;
    }
    public static void uniformInt(int location, int value) {
        Location entry = LOCATIONS.get(location);
        if (entry == null)
            return;
        if (entry.sampler >= 0)
            entry.program.units[entry.sampler] = value;
        else
            entry.program.data.putInt(entry.offset, value);
    }
    public static void uniformValues(int location, IntBuffer values) {
        Location entry = LOCATIONS.get(location);
        if (entry == null)
            return;
        if (entry.sampler >= 0) {
            entry.program.units[entry.sampler] = values.get(values.position());
            return;
        }
        for (int i = 0; i < Math.min(entry.count, values.remaining()); i++)
            entry.program.data.putInt(entry.offset + i * 4, values.get(values.position() + i));
    }
    public static void uniformValues(int location, FloatBuffer values) {
        Location entry = LOCATIONS.get(location);
        if (entry == null)
            return;
        for (int i = 0; i < Math.min(entry.count, values.remaining()); i++)
            entry.program.data.putFloat(entry.offset + i * 4, values.get(values.position() + i));
    }
}
