#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

# PCB-confirmed standard static non-flipped diagnostic.
# white_middle: raw X=$71, raw Y=$F0 -> about hdump=145, vdump=255.
MZONE_GRID_NAME=tnoflip_standard_static \
MZONE_GRID_SCROLLY=0 \
MZONE_RED_FIX_BOX=1 \
MZONE_YELLOW_FIX_BOX=1 \
MZONE_SPRITE_X0=1 \
MZONE_SPRITE_X10=1 \
MZONE_SPRITE_X239=1 \
MZONE_WHITE_MIDDLE=1 \
MZONE_WHITE_MIDDLE_X=0x7A \
MZONE_WHITE_MIDDLE_Y=0xE0 \
MZONE_SCREEN_FLIP=0 \
    python3 make_pcb_testrom_6h.py

# Exact flipped counterpart. PCB-confirmed X conversion is
# General mapping: Xflip=(250-Xnormal), Yflip=(241-Ynormal), modulo 256.
MZONE_GRID_NAME=tflip_standard_static \
MZONE_GRID_SCROLLY=0 \
MZONE_RED_FIX_BOX=1 \
MZONE_YELLOW_FIX_BOX=1 \
MZONE_WHITE_EDGES=1 \
MZONE_WHITE_EDGE_TOP_X=0 \
MZONE_FLIPPED_X_ADJUST=1 \
MZONE_FLIPPED_Y_MIRROR=1 \
MZONE_FLIPPED_Y_ADJUST=1 \
MZONE_FLIPPED_ATTR_TOGGLE=0x00 \
MZONE_WHITE_MIDDLE=1 \
MZONE_WHITE_MIDDLE_X=0x81 \
MZONE_WHITE_MIDDLE_Y=0x12 \
MZONE_WHITE_MIDDLE_ATTR=0x4E \
MZONE_FLIP_WHITE_X255=1 \
MZONE_SCREEN_FLIP=1 \
    python3 make_pcb_testrom_6h.py

sha256sum \
    tnoflip_standard_static_6h.bin \
    tnoflip_standard_static_6h_sim.rom \
    tflip_standard_static_6h.bin \
    tflip_standard_static_6h_sim.rom
