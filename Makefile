# Connect Four game controller: lint, simulation, formal verification, synthesis.
# Toolchain: Icarus Verilog, Verilator, Yosys + yosys-abc + yosys-smtbmc, Z3, Python 3
# (exact versions in scripts/install-tools.sh).

RTL := rtl/connect4.sv
TB  := tb/tb_connect4.sv
RUN := bash scripts/run_sim.sh

.PHONY: all ci full summary lint sim sim-icarus sim-verilator formal formal-quick synth games clean

all: lint sim

# CI entry points (.github/workflows): `make ci` runs on every push, `make full` adds the full-board check
ci: lint sim formal-quick synth summary
full: lint sim formal synth summary

summary:
	@bash scripts/summary.sh > /dev/null && echo "wrote build/SUMMARY.md"

lint:
	verilator --lint-only -Wall --top-module connect4 $(RTL)

sim: sim-icarus sim-verilator

sim-icarus:
	$(RUN) icarus connect4 $(TB) "" $(RTL)

sim-verilator:
	$(RUN) verilator connect4 $(TB) "" $(RTL)

# PDR proof on a 4 x 4 board, mutation check, BMC of the full board (BIG=1 also tries a 4 x 5 proof)
formal:
	bash formal/run_formal.sh

# the same without the full-board BMC (about 6 minutes)
formal-quick:
	QUICK=1 bash formal/run_formal.sh

synth:
	bash scripts/synth.sh

# regenerate the directed games of the testbench (shortest random games that end in each kind of win)
games:
	python3 scripts/c4model.py tb/directed_games.svh

clean:
	rm -rf build obj_dir
