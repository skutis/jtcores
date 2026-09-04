#!/bin/bash

SIM_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
MZONE_ROM=${MZONE_ROM:-$ROM/${MZONE_SETNAME:-megazone}.rom}

SCENE=
SIM_ARGS=()
while (( $# )); do
    case "$1" in
        -s|-scene)
            if (( $# < 2 )); then
                echo "Missing scene directory after $1" >&2
                exit 1
            fi
            SCENE=$2
            shift 2
            ;;
        *)
            SIM_ARGS+=("$1")
            shift
            ;;
    esac
done

if [[ -n "$SCENE" ]]; then
    if [[ ! -d "$SCENE" && -d "$SIM_DIR/scenes/$SCENE" ]]; then
        SCENE="$SIM_DIR/scenes/$SCENE"
    fi
    [[ -d "$SCENE" ]] || { echo "Cannot find scene $SCENE" >&2; exit 1; }
    scene_files=(vram0.bin vram1.bin cram0.bin cram1.bin obj.bin shared.bin regs.hex)
    scene_missing=0
    for scene_file in "${scene_files[@]}"; do
        [[ -f "$SCENE/$scene_file" ]] || scene_missing=1
    done
    if (( scene_missing )) && [[ -f "$SCENE/scene.lua" ]]; then
        echo "Recreating scene data in $SCENE"
        bash "$SIM_DIR/scenes/capture.sh" "$SCENE" || exit 1
    fi
    for scene_file in "${scene_files[@]}"; do
        [[ -f "$SCENE/$scene_file" ]] || {
            echo "Scene $SCENE is missing $scene_file" >&2
            exit 1
        }
        cp "$SCENE/$scene_file" "$scene_file" || exit 1
    done
    cp shared.bin main_shared.bin || exit 1
    SIM_ARGS=(-d SIMSCENE -d NOMAIN -video 3 "${SIM_ARGS[@]}")
fi
set -- "${SIM_ARGS[@]}"

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
# Verilator 5.046 can reuse stale generated objects across trace/non-trace
# layouts through ccache/PCH, producing a trace-only crash in ctor_var_reset.
export OBJCACHE=${OBJCACHE:-}

jtsim -mist -sysname mzone -load -verilator "$@"
