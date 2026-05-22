#!/bin/bash

MZONE_ROM=${MZONE_ROM:-$ROM/${MZONE_SETNAME:-megazone}.rom}

if [ ! -e rom.bin ] || [ "$(readlink -f rom.bin)" != "$(readlink -f "$MZONE_ROM")" ]; then
    ln -srf "$MZONE_ROM" rom.bin || exit 1
fi

if [ -z "$MZONE_SOUND" ]; then
    set -- -d MZONE_FAST_SOUND "$@"
fi

if [ -n "$MZONE_THREADS" ]; then
    set -- -args "--threads $MZONE_THREADS" "$@"
fi

if [ -n "$MZONE_SAVE_FRAME" ]; then
    export JTFRAME_SAVE_FRAME="$MZONE_SAVE_FRAME"
fi

if [ -n "$MZONE_SAVE_FILE" ]; then
    export JTFRAME_SAVE_FILE="$MZONE_SAVE_FILE"
fi

if [ -n "$MZONE_LOAD_FILE" ]; then
    export JTFRAME_LOAD_FILE="$MZONE_LOAD_FILE"
fi

if [ -n "$MZONE_SAVABLE" ] || [ -n "$MZONE_SAVE_FRAME" ] || [ -n "$MZONE_LOAD_FILE" ]; then
    set -- -d JTFRAME_SAVABLE -args "--savable" "$@"
fi

export FRAMERATE=${FRAMERATE:-60}
export CCACHE_DIR=${CCACHE_DIR:-/tmp/ccache}
export CCACHE_TEMPDIR=${CCACHE_TEMPDIR:-/tmp/ccache-tmp}

jtsim -mist -sysname mzone -load -verilator "$@"
