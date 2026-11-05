/*
 * PortTime for AmigaOS 3.x: milliseconds since Pt_Start() from the time of
 * day, and the periodic callback on its own thread (libpthread), woken on
 * each multiple of the resolution.
 * Copyright (c) 2026 AmiCradle Team
 */
#include <stdlib.h>
#include <sys/time.h>
#include <unistd.h>
#include <pthread.h>
#include "porttime.h"

static int started;
static struct timeval offset;
static pthread_t thread;
static int thread_made;
static volatile int run_id;

struct pt_params {
    int id;
    int resolution;
    PtCallback *callback;
    void *userData;
};

static void *pt_thread(void *p)
{
    struct pt_params *pp = (struct pt_params *)p;
    int tick = 1;
    while (run_id == pp->id) {
        int delay = tick++ * pp->resolution - Pt_Time();
        if (delay > 0)
            usleep((useconds_t)delay * 1000);
        (*pp->callback)(Pt_Time(), pp->userData);
    }
    free(pp);
    return NULL;
}

PtError Pt_Start(int resolution, PtCallback *callback, void *userData)
{
    if (started)
        return ptAlreadyStarted;
    gettimeofday(&offset, NULL);
    if (callback) {
        struct pt_params *pp = (struct pt_params *)malloc(sizeof *pp);
        if (!pp)
            return ptInsufficientMemory;
        pp->id = ++run_id;
        pp->resolution = resolution > 0 ? resolution : 1;
        pp->callback = callback;
        pp->userData = userData;
        if (pthread_create(&thread, NULL, pt_thread, pp) != 0) {
            free(pp);
            return ptHostError;
        }
        thread_made = 1;
    }
    started = 1;
    return ptNoError;
}

PtError Pt_Stop(void)
{
    if (!started)
        return ptAlreadyStopped;
    run_id++;
    if (thread_made) {
        pthread_join(thread, NULL);
        thread_made = 0;
    }
    started = 0;
    return ptNoError;
}

int Pt_Started(void)
{
    return started;
}

PtTimestamp Pt_Time(void)
{
    struct timeval now;
    gettimeofday(&now, NULL);
    return (PtTimestamp)((now.tv_sec - offset.tv_sec) * 1000
                         + (now.tv_usec - offset.tv_usec) / 1000);
}

void Pt_Sleep(int32_t duration)
{
    if (duration > 0)
        usleep((useconds_t)duration * 1000);
}
