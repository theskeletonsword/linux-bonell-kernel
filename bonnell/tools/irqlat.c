// SPDX-License-Identifier: GPL-2.0
/*
 * irqlat - minimal timer wake-up latency probe for the Bonnell initramfs.
 *
 * A SCHED_FIFO thread sleeps with clock_nanosleep(TIMER_ABSTIME) on
 * CLOCK_MONOTONIC at a fixed period and records how late it wakes up, the
 * same measurement cyclictest(8) makes. The figure covers the hrtimer
 * interrupt, IRQ entry/exit, the wakeup and the context switch back to the
 * thread. Alpine has no rt-tests package, hence this tool.
 *
 * Usage: irqlat [loops=5000] [period_us=1000]
 * Output: one line, "irqlat: loops=N period_us=P min= avg= p50= p99= max= (ns)"
 *
 * Build: gcc -O2 -static -pthread -Wall -Wextra -Werror -o irqlat irqlat.c
 *
 * musl implements sched_setscheduler() as ENOSYS on purpose (the syscall is
 * per thread, POSIX's function is per process), so the real-time policy is
 * set with pthread_setschedparam() on the calling thread.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <limits.h>
#include <pthread.h>
#include <sched.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>

#define NSEC_PER_SEC 1000000000LL

static long long ts_ns(const struct timespec *t)
{
	return (long long)t->tv_sec * NSEC_PER_SEC + t->tv_nsec;
}

static int cmp_ll(const void *a, const void *b)
{
	long long x = *(const long long *)a, y = *(const long long *)b;

	return (x > y) - (x < y);
}

static long parse_arg(const char *s, long def, long lo, long hi)
{
	char *end;
	long v;

	if (!s)
		return def;
	errno = 0;
	v = strtol(s, &end, 10);
	if (errno || *end || v < lo || v > hi) {
		fprintf(stderr, "irqlat: bad argument '%s' (range %ld..%ld)\n",
			s, lo, hi);
		exit(2);
	}
	return v;
}

int main(int argc, char **argv)
{
	long loops = parse_arg(argc > 1 ? argv[1] : NULL, 5000, 10, 10000000);
	long period_us = parse_arg(argc > 2 ? argv[2] : NULL, 1000, 50, 1000000);
	struct sched_param sp = { .sched_priority = 80 };
	struct timespec next, now;
	long long *lat, sum = 0;
	const char *policy = "SCHED_FIFO";
	long i;
	int err;

	lat = calloc((size_t)loops, sizeof(*lat));
	if (!lat) {
		perror("irqlat: calloc");
		return 1;
	}
	if (mlockall(MCL_CURRENT | MCL_FUTURE))
		perror("irqlat: mlockall (continuing)");
	err = pthread_setschedparam(pthread_self(), SCHED_FIFO, &sp);
	if (err) {
		fprintf(stderr, "irqlat: SCHED_FIFO: %s (continuing as SCHED_OTHER)\n",
			strerror(err));
		policy = "SCHED_OTHER";
	}

	clock_gettime(CLOCK_MONOTONIC, &next);
	for (i = 0; i < loops; i++) {
		int ret;

		next.tv_nsec += period_us * 1000;
		while (next.tv_nsec >= NSEC_PER_SEC) {
			next.tv_nsec -= NSEC_PER_SEC;
			next.tv_sec++;
		}
		do {
			ret = clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME,
					      &next, NULL);
		} while (ret == EINTR);
		if (ret) {
			fprintf(stderr, "irqlat: clock_nanosleep: %s\n",
				strerror(ret));
			return 1;
		}
		clock_gettime(CLOCK_MONOTONIC, &now);
		lat[i] = ts_ns(&now) - ts_ns(&next);
		sum += lat[i];
	}

	qsort(lat, (size_t)loops, sizeof(*lat), cmp_ll);
	printf("irqlat: policy=%s loops=%ld period_us=%ld min=%lld avg=%lld p50=%lld p99=%lld max=%lld (ns)\n",
	       policy, loops, period_us, lat[0], sum / loops, lat[loops / 2],
	       lat[(loops * 99) / 100], lat[loops - 1]);
	free(lat);
	return 0;
}
