package mcopt.legacy;

import mcopt.metal.FrameDeadline;
import org.junit.Test;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

public final class LegacyPacingTest {
	@Test
	public void timerLoadsThroughJni() {
		if (System.getProperty("os.name").startsWith("Mac")) assertTrue(LegacyNative.available());
	}

	@Test
	public void timerDoesNotReturnBeforeDeadline() {
		long deadline = System.nanoTime() + 2_000_000;
		LegacyNative.sleepUntil(deadline);
		assertTrue(System.nanoTime() >= deadline);
	}

	@Test
	public void expiredDeadlineReturnsPromptly() {
		long now = System.nanoTime();
		LegacyNative.sleepUntil(now - 1_000_000);
		assertTrue(System.nanoTime() - now < 100_000_000);
	}

	@Test
	public void interruptIsPreserved() {
		Thread.currentThread().interrupt();
		try {
			LegacyNative.sleepUntil(System.nanoTime());
			assertTrue(Thread.currentThread().isInterrupted());
		} finally {
			Thread.interrupted();
		}
	}

	@Test
	public void deadlineCadenceSurvivesTimerJitter() {
		FrameDeadline deadlines = new FrameDeadline();
		long period = 1_000_000_000L / 180;
		long start = 1_000_000_000L, last = start;
		for (int i = 0; i < 2000; i++) {
			long deadline = deadlines.next(last + period / 4, last, 180);
			assertEquals(start + (i + 1L) * period, deadline);
			last = deadline + 30_000;
		}
		long stalled = last + 50_000_000;
		assertTrue(deadlines.next(stalled, last, 180) <= stalled);
	}
}
