package mcopt.legacy;

import mcopt.metal.FrameDeadline;

public final class LegacyFramePacing {
	public static final boolean PRECISE = Boolean.parseBoolean(System.getProperty("meshnet.preciseLimiter", "true"));
	public static final boolean SMOOTH = Boolean.parseBoolean(System.getProperty("meshnet.smooth", "false"));
	private static final FrameDeadline DEADLINES = new FrameDeadline();
	private static long lastFrame;

	private LegacyFramePacing() {
	}

	public static void limit(int framesPerSecond) {
		LegacyNative.sleepUntil(DEADLINES.next(System.nanoTime(), lastFrame, framesPerSecond));
		lastFrame = System.nanoTime();
	}
}
