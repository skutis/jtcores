SHELL     := /bin/bash
ENV_SH    := ../../env.sh
VERILATOR ?= verilator
IVERILOG  ?= iverilog
VVP       ?= vvp
TOP       := tb_hcnt
ROM_BIN   ?= ../../ver/game/rom.bin
US        ?= 1000
JTFRAME_PROM := ../../../../modules/jtframe/hdl/ram/jtframe_prom.v
SRCS      := tb_hcnt.v jtmzone_hcnt.v $(JTFRAME_PROM)

VFLAGS := --binary --trace -DSIMULATION -DJTFRAME_PROM_START=22\'h1F000 \
          -Wno-DECLFILENAME -Wno-BLKSEQ -Wno-UNUSEDSIGNAL
IVFLAGS := -g2012 -DSIMULATION -DJTFRAME_PROM_START=22\'h1F000

.PHONY: all run ivl run-ivl clean

all: obj_dir/V$(TOP)

obj_dir/V$(TOP): $(SRCS)
	source $(ENV_SH); CCACHE_DISABLE=1 $(VERILATOR) $(VFLAGS) --top-module $(TOP) $(SRCS)

run: obj_dir/V$(TOP) $(ROM_BIN)
	source $(ENV_SH); ./obj_dir/V$(TOP) +US=$(US)

hcnt.vvp: $(SRCS)
	$(IVERILOG) $(IVFLAGS) -s $(TOP) -o $@ $(SRCS)

ivl: hcnt.vvp

run-ivl: hcnt.vvp $(ROM_BIN)
	$(VVP) hcnt.vvp +US=$(US)

clean:
	rm -rf obj_dir hcnt.vcd hcnt.vvp
