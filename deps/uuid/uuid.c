/*
 * libuuid for AmigaOS 3.x: version 4 (random) UUIDs. The randomness is a
 * xorshift generator seeded from the time of day, the task's address, the
 * E-clock and a count, mixed again at every call: unique enough for
 * Audacity's project and session ids, not for cryptography.
 * Copyright (c) 2026 AmiCradle Team
 */
#include <string.h>
#include <stdio.h>
#include <sys/time.h>
#include <proto/exec.h>
#include "uuid/uuid.h"

static unsigned long long s_state;
static unsigned long s_count;

static unsigned long long next64(void)
{
    unsigned long long x = s_state;
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    s_state = x;
    return x * 0x2545F4914F6CDD1DULL;
}

static void mix(void)
{
    struct timeval tv;
    gettimeofday(&tv, NULL);
    s_state ^= ((unsigned long long)tv.tv_sec << 32) ^ (unsigned long long)tv.tv_usec;
    s_state ^= (unsigned long long)(unsigned long)FindTask(NULL) << 16;
    s_state ^= (unsigned long long)(++s_count) * 0x9E3779B97F4A7C15ULL;
    if (!s_state)
        s_state = 0x853c49e6748fea9bULL;
    next64();
}

void uuid_generate_random(uuid_t out)
{
    unsigned long long a, b;
    Forbid();
    mix();
    a = next64();
    b = next64();
    Permit();
    memcpy(out, &a, 8);
    memcpy(out + 8, &b, 8);
    out[6] = (unsigned char)((out[6] & 0x0f) | 0x40);  /* version 4 */
    out[8] = (unsigned char)((out[8] & 0x3f) | 0x80);  /* RFC 4122 variant */
}

void uuid_generate(uuid_t out)
{
    uuid_generate_random(out);
}

static void unparse(const uuid_t uu, char *out, const char *digits)
{
    int i, o = 0;
    for (i = 0; i < 16; i++) {
        if (i == 4 || i == 6 || i == 8 || i == 10)
            out[o++] = '-';
        out[o++] = digits[uu[i] >> 4];
        out[o++] = digits[uu[i] & 15];
    }
    out[o] = 0;
}

void uuid_unparse(const uuid_t uu, char *out) { unparse(uu, out, "0123456789abcdef"); }
void uuid_unparse_lower(const uuid_t uu, char *out) { unparse(uu, out, "0123456789abcdef"); }
void uuid_clear(uuid_t uu) { memset(uu, 0, 16); }

int uuid_is_null(const uuid_t uu)
{
    int i;
    for (i = 0; i < 16; i++)
        if (uu[i])
            return 0;
    return 1;
}
