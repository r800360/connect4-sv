# Connect Four game controller - lint, simulation, formal verification and synthesis statistics.
# Tools: Verilator >= 5, Icarus Verilog >= 12, Yosys >= 0.30 (with yosys-smtbmc, yosys-abc) and Z3.
RTL   := rtl/connect4.sv
TB    := tb/tb_connect4.sv
BUILD := build

.PHONY: all lint sim sim-icarus sim-verilator formal synth games clean

all: lint sim

lint:
	verilator --lint-only -Wall --top-module connect4 $(RTL)

sim: sim-icarus sim-verilator

sim-icarus:
	@mkdir -p $(BUILD)
	iverilog -g2012 -I tb -o $(BUILD)/tb.vvp $(TB) $(RTL)
	vvp -n $(BUILD)/tb.vvp | tee $(BUILD)/icarus.log
	@grep -q "RESULT: PASS" $(BUILD)/icarus.log

sim-verilator:
	@mkdir -p $(BUILD)
	verilator --binary --timing -Wno-fatal -Itb --top-module tb_connect4 -Mdir $(BUILD)/verilator $(TB) $(RTL)
	$(BUILD)/verilator/Vtb_connect4 | tee $(BUILD)/verilator.log
	@grep -q "RESULT: PASS" $(BUILD)/verilator.log

# unbounded PDR proofs on a 4x4 board, mutation check, BMC of the full board (BIG=1 adds a 4x5 connect-4 proof)
formal:
	bash formal/run_formal.sh

# gate-level statistics of the default 6x7 configuration
synth:
	@mkdir -p $(BUILD)
	yosys -q -p "read_verilog -sv $(RTL); synth -top connect4 -flatten; abc -g gates; \
	  opt_clean; tee -o $(BUILD)/synth_stat.txt stat" && cat $(BUILD)/synth_stat.txt

# regenerate the directed games of the testbench (shortest random games that end in each kind of win)
games:
	python3 scripts/c4model.py tb/directed_games.svh

clean:
	rm -rf $(BUILD)
