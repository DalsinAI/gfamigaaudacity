/* dlfcn.h for C++ on m68k-amigaos: libnix's own header has no C linkage
 * block, so C++ callers (Audacity's lib-vst) would look for mangled names
 * instead of libnix's dlopen() and friends.
 * Copyright (c) 2026 AmiCradle Team */
#ifndef AMIGAAUDACITY_DLFCN_H
#define AMIGAAUDACITY_DLFCN_H
#ifdef __cplusplus
extern "C" {
#endif
#include_next <dlfcn.h>
#ifdef __cplusplus
}
#endif
#endif
