#!/bin/bash

if [ ! -e rom.bin ]; then
    ln -s $ROM/megazone.rom rom.bin || exit 1
fi

jtsim -mist -sysname mzone -load -verilator $*

