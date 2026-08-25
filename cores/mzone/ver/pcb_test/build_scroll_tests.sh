#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

build_scroll_test() {
    local name=$1
    local flip=$2
    local divider=${3:-1}

    MZONE_GRID_NAME="$name" \
    MZONE_GRID_SCROLLY=0 \
    MZONE_RED_FIX_BOX=1 \
    MZONE_YELLOW_FIX_BOX=1 \
    MZONE_SPRITE_X0=1 \
    MZONE_SPRITE_X10=1 \
    MZONE_SPRITE_X239=1 \
    MZONE_SMOOTH_SCROLL=1 \
    MZONE_SCREEN_FLIP="$flip" \
    MZONE_SCROLL_DIV="$divider" \
        python3 make_pcb_testrom_6h.py
}

build_scroll_test tscr4  0
build_scroll_test tscr4f 1
build_scroll_test tscr4fs 1 4

sha256sum \
    tscr4_6h.bin tscr4_6h_sim.rom \
    tscr4f_6h.bin tscr4f_6h_sim.rom \
    tscr4fs_6h.bin tscr4fs_6h_sim.rom
