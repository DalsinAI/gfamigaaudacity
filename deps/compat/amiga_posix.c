/* amiga_posix.c - the POSIX calls Audacity links that libnix lacks.
 *
 * fchmod/fchown: SQLite matches a journal's owner and mode to its database.
 * AmigaOS has neither in that sense, so both succeed without doing anything.
 *
 * exp2f: libnix's libm has expf but not exp2f (Audacity's formant shifter).
 *
 * Copyright (c) 2026 AmiCradle Team */
#include <sys/types.h>
#include <math.h>

int fchmod(int fd, mode_t mode) { (void)fd; (void)mode; return 0; }
int fchown(int fd, uid_t uid, gid_t gid) { (void)fd; (void)uid; (void)gid; return 0; }

/* 2^x = e^(x ln 2); built with -fno-builtin so this stays a call to expf */
float exp2f(float x) { return expf(x * 0.693147180559945309f); }
