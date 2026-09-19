#!/bin/bash
# Shared setup for fixed PCB test presets; low-level generators still accept
# MZONE_* overrides when invoked directly for experiments.
PCB_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PCB_ROOT=$(cd -- "$PCB_DIR/../../../.." && pwd)

prepare_preset() {
    local variable actual
    # A named preset must not inherit settings from an earlier experiment.
    for variable in ${!MZONE_@}; do
        unset "$variable"
    done
    cd -- "$PCB_DIR"
    local base_rom="$PCB_ROOT/rom/megazone.rom"
    local expected=8d5b0340c55a5710aa5877246b09acaba0a1cde08637c82feded22898ba1905f
    actual=$(sha256sum "$base_rom" 2>/dev/null) || actual=
    if [[ ${actual%% *} != "$expected" ]]; then
        echo "Missing or unverified base ROM: $base_rom" >&2
        echo "Expected SHA-256: $expected" >&2
        echo 'Source the core env.sh, then rebuild with: jtframe mra mzone --path "$HOME/.mame/roms" -v' >&2
        echo 'Use the documented MAME 0.251 ZIP and current ROM packing rules.' >&2
        return 1
    fi
    # Check that the current OBJ layout still matches the verified artifact.
    python3 - "$PCB_ROOT/cores/mzone/cfg/mame2mra.toml" <<'PY'
import re
import sys
from pathlib import Path
# Validate the core's inline gfx1 rule without an extra TOML dependency.
text = "\n".join(line.split("#", 1)[0] for line in Path(sys.argv[1]).read_text().splitlines())
obj = next((entry for entry in re.findall(r"\{[^{}]*\}", text)
            if re.search(r'\bname\s*=\s*"gfx1"', entry)), "")
if not (re.search(r"\bwidth\s*=\s*16\s*[,}]", obj)
        and re.search(r"\bsequence\s*=\s*\[\s*0\s*,\s*2\s*,\s*1\s*,\s*3\s*\]", obj)):
    sys.exit("OBJ ROM packing changed: expected width=16, sequence=[0,2,1,3]. Review the test fixtures before rebuilding.")
PY
}

check_grid_capture() {
    if ! sha256sum --check --status grid_capture.sha256; then
        echo "Grid capture missing or changed. See ver/README.md; no derived boundary ROMs were built." >&2
        return 1
    fi
}
