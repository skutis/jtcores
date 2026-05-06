SHELL     := /bin/bash
ENV_SH    := ../../env.sh
VERILATOR ?= verilator
TOP       := tb_hcnt
ROM_BIN   ?= ../../ver/game/rom.bin
US        ?= 1000

VFLAGS := --binary --trace -DSIMULATION -DJTFRAME_PROM_START=22\'h1F000 \
          -Wno-DECLFILENAME -Wno-BLKSEQ -Wno-UNUSEDSIGNAL

.PHONY: all run clean

all: obj_dir/V$(TOP)

obj_dir/V$(TOP): tb_hcnt.v jtmzone_hcnt.v
	source $(ENV_SH); CCACHE_DISABLE=1 $(VERILATOR) $(VFLAGS) --top-module $(TOP) tb_hcnt.v jtmzone_hcnt.v

run: obj_dir/V$(TOP)
	source $(ENV_SH); ./obj_dir/V$(TOP) +ROM=$(ROM_BIN) +US=$(US)

clean:
	rm -rf obj_dir hcnt.vcd
