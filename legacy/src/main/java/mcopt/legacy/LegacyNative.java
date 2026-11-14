package mcopt.legacy;

import java.io.InputStream;
import java.nio.ByteBuffer;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.util.Locale;
import java.util.concurrent.locks.LockSupport;

public final class LegacyNative {
    private static final boolean AVAILABLE = load();

    private LegacyNative() {}

    private static boolean load() {
        if (!System.getProperty("os.name", "").toLowerCase(Locale.ROOT).contains("mac"))
            return false;
        try (InputStream stream = LegacyNative.class.getResourceAsStream("/natives/libmeshnet116.dylib")) {
            if (stream == null)
                return false;
            Path directory = Files.createTempDirectory("meshnet-116-");
            Path library = directory.resolve("libmeshnet116.dylib");
            Files.copy(stream, library, StandardCopyOption.REPLACE_EXISTING);
            directory.toFile().deleteOnExit();
            library.toFile().deleteOnExit();
            System.load(library.toAbsolutePath().toString());
            return true;
        } catch (Exception | LinkageError error) {
            System.err.println("meshnet: native timer unavailable: " + error.getMessage());
            return false;
        }
    }

    public static boolean available() { return AVAILABLE; }

    public static void sleepUntil(long deadline) {
        for (long remaining; (remaining = deadline - System.nanoTime()) > 0;) {
            if (AVAILABLE)
                sleep0(remaining);
            else if (remaining > 150_000)
                LockSupport.parkNanos(remaining - 100_000);
            if (Thread.currentThread().isInterrupted())
                return;
        }
    }

    private static native void sleep0(long nanos);
}
