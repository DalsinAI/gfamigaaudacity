/*
 * PortMidi's system part for AmigaOS 3.x: no MIDI devices yet (a
 * camd.library backend comes later), so Pm_CountDevices() is 0 and
 * Audacity's note tracks load, edit and save, with nothing to play to.
 * PortMidi's own portmidi.c and pmutil.c are fetched at build time.
 * Copyright (c) 2026 AmiCradle Team
 */
#include <stdlib.h>
#include "portmidi.h"
#include "pmutil.h"
#include "pminternal.h"

PmDeviceID pm_default_input_device_id = -1;
PmDeviceID pm_default_output_device_id = -1;

void pm_init(void)
{
    pm_initialized = TRUE;
}

void pm_term(void)
{
}

PmDeviceID Pm_GetDefaultInputDeviceID(void)
{
    Pm_Initialize();
    return pm_default_input_device_id;
}

PmDeviceID Pm_GetDefaultOutputDeviceID(void)
{
    Pm_Initialize();
    return pm_default_output_device_id;
}

void *pm_alloc(size_t s) { return malloc(s); }

void pm_free(void *ptr) { free(ptr); }
