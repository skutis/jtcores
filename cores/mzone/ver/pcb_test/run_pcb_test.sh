#!/bin/bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
device=${PICOROM_DEVICE:-}

if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "Usage: $0 <test-name|rom.bin> [device]" >&2
    echo "Example: $0 tscr_1000_dec" >&2
    exit 2
fi

test_rom=$1
device=${2:-$device}

if [[ -z $device ]]; then
    mapfile -t device_names < <(
        picorom list | sed -n 's/.*\[\([^][]*\)\][[:space:]]*$/\1/p'
    )
    if [[ ${#device_names[@]} -ne 1 ]]; then
        echo "Expected exactly one PicoROM; found ${#device_names[@]}." >&2
        echo "Pass its name as argument 2 or set PICOROM_DEVICE." >&2
        picorom list >&2
        exit 1
    fi
    device=${device_names[0]}
fi

if [[ $test_rom != */* && $test_rom != *.bin ]]; then
    test_rom="${script_dir}/${test_rom}_6h.bin"
elif [[ $test_rom != */* ]]; then
    test_rom="${script_dir}/${test_rom}"
fi

if [[ ! -f $test_rom ]]; then
    echo "ROM not found: $test_rom" >&2
    exit 1
fi

# PicoROM includes the basename as rom_name. Keep it short enough for the
# request packet even when the source test has a descriptive filename.
upload_rom=$(mktemp /tmp/prXXXXXX.bin)
cleanup() {
    rm -f -- "$upload_rom"
}
trap cleanup EXIT
cp -- "$test_rom" "$upload_rom"

echo "Uploading $(basename -- "$test_rom") to $device"
picorom upload "$device" "$upload_rom" 64KBit

if [[ ${PICOROM_COMMIT:-0} == 1 ]]; then
    echo "Committing ROM to PicoROM flash"
    picorom commit "$device"
fi

echo "Resetting PCB"
picorom reset "$device" low
sleep 1
picorom reset "$device" z

echo "Running $(basename -- "$test_rom")"
