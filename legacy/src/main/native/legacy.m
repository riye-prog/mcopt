#include <errno.h>
#include <jni.h>
#include <stdint.h>
#include <stdlib.h>
#include <sys/event.h>
#include <time.h>
#include <unistd.h>

#ifdef __cplusplus
extern "C"
#endif
JNIEXPORT void JNICALL Java_mcopt_legacy_LegacyNative_sleep0(JNIEnv *environment, jclass type, jlong nanos) {
    (void)environment;
    (void)type;
    static __thread int queue = -1;
    if (nanos <= 0)
        return;
    if (queue < 0)
        queue = kqueue();
    struct kevent64_s timer, result;
    EV_SET64(&timer, 1, EVFILT_TIMER, EV_ADD | EV_ONESHOT, NOTE_NSECONDS | NOTE_CRITICAL | NOTE_LEEWAY, nanos,
             0, 0, 0);
    if (queue >= 0 && kevent64(queue, &timer, 1, &result, 1, 0, NULL) >= 0)
        return;
    struct timespec remaining = {nanos / 1000000000, nanos % 1000000000};
    while (nanosleep(&remaining, &remaining) < 0 && errno == EINTR) {
    }
}
