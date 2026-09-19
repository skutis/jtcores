#!/bin/bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
prepare_preset
check_grid_capture

bash "$PCB_DIR/build_static_tests.sh"
bash "$PCB_DIR/build_scroll_tests.sh"
bash "$PCB_DIR/build_boundary_tests.sh"
