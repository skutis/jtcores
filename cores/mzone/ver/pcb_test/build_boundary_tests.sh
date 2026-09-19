#!/bin/bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
prepare_preset
check_grid_capture

# Rebuild every dependency; never derive the FIX test from an old test ROM.
MZONE_GRID_NAME=megazone_grid_scrollp1px MZONE_GRID_SCROLLY=0xFF \
    python3 make_pcb_grid_6h.py
python3 make_boundary_scrollff_test.py
python3 make_fix_boundary_test.py

sha256sum megazone_grid_scrollp1px_6h.bin megazone_grid_scrollp1px_6h_sim.rom \
    tboundary_scrollff_6h.bin tboundary_scrollff_6h_sim.rom \
    tfix_boundary_6h.bin tfix_boundary_6h_sim.rom
