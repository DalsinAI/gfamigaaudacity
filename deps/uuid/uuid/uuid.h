/*
 * uuid/uuid.h for AmigaOS 3.x: the part of libuuid's interface Audacity
 * uses (uuid_generate), as AmiCradle's own code.
 * Copyright (c) 2026 AmiCradle Team
 */
#ifndef AMIGA_UUID_H
#define AMIGA_UUID_H

#ifdef __cplusplus
extern "C" {
#endif

typedef unsigned char uuid_t[16];

void uuid_generate(uuid_t out);
void uuid_generate_random(uuid_t out);
void uuid_unparse(const uuid_t uu, char *out);      /* 36 characters and a 0 */
void uuid_unparse_lower(const uuid_t uu, char *out);
void uuid_clear(uuid_t uu);
int uuid_is_null(const uuid_t uu);

#ifdef __cplusplus
}
#endif

#endif
