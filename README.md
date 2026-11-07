# GF Amiga Audacity

Audacity 3.7.9 for AmigaOS 3 (68040, soft float), on the GFOpenWX Toolkit (wxWidgets on GFOpenLayout) and GFOpenPortAudio (PortAudio on AHI).

Audacity and the libraries it uses are fetched at build time at the versions `audacity.lock` pins, and `patches/` is applied to them; nothing third-party is kept in this repository.

## What works

- Starts, builds every toolbar, imports WAV, draws the waveform, plays at 44100 Hz through AHI.
- Menus with their Amiga-key shortcuts; Preferences (every page, scrolling).
- Projects in SQLite through an Amiga file system layer (patch 0014).

Owed: recording (needs an AHI mode that records), MIDI, a smaller binary (about 38 MB), speed.

## Building

```
STOVE=~/AmiCradle/stoves/os32-gcc16-open6 OUT=out ./build-amiga.sh
```

The first run fetches the GFOpenWX Toolkit and GFOpenPortAudio at the commits `audacity.lock` pins, builds the toolkit SDK, PortAudio and the libraries (libsndfile, LAME, SoundTouch, PortMidi, RapidJSON), then Audacity for what is left of 840 s; run it again and it goes on from where it stopped (the build tree is kept in `~/.cache/gfamigaaudacity/build`, or `WORK`). `out/audacity` appears when it links, next to `out/Audacity.info`, its Workbench icon. Copy both into a drawer as `Audacity` and `Audacity.info`; a double-click runs it (the program asks for its own 1 MB stack and makes its `Temp` drawer).

| Where | What |
|---|---|
| `patches/` | Audacity's changes for the Amiga: static modules, paths, big-endian sample blocks, the SQLite VFS, the main entry |
| `scripts/` | build-deps.sh, build-audacity.sh, the theme compiler run on the host |
| `cmake/` | the m68k-amigaos toolchain and platform files |
| `deps/` | the small pieces libnix lacks (POSIX calls, uuid, PortMidi's Amiga host) |

## ARexx

Audacity has an ARexx port, `AUDACITY.1`, from the GFOpenWX Toolkit's `wxARexxPort` on arexx.class (patch 0015). `DO` takes any of Audacity's scripting commands, as mod-script-pipe and Nyquist's `aud-do` take them.

| Command | Does |
| --- | --- |
| `OPEN FILE/A` | open a project or audio file, as a second start does |
| `DO COMMAND/F` | one scripting command (`Select: Start=0 End=5`); RESULT: its answer; RC 10 when it failed |
| `PLAY`, `STOP` | the Play and Stop commands |
| `QUIT`, `ACTIVATE`, `DEACTIVATE`, `VERSION`, `HELP`, `FAULT` | the toolkit's standard commands |

```
/* Audacity: louder first five seconds, then save as WAV */
OPTIONS RESULTS
ADDRESS 'AUDACITY.1'
'DO Select: Start=0 End=5'
'DO Amplify: Ratio=1.5'
'DO Export2: Filename="Work:Sounds/louder.wav"'
'DO GetInfo: Type=Tracks'
SAY result
```

## Licence

Audacity is GPL v2 or later; the patches and build files here are under the same licence.

Designed, tested and delivered by The AmiCradle Team.
Copyright (c) 2026 AmiCradle Team
