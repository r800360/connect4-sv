#!/bin/bash
# synth.sh - Yosys synthesis of the default 6 x 7 configuration to a generic gate library (synth -flatten;
# abc -g gates). Writes build/synth/summary.txt (cell counts), stat.txt (full statistics) and connect4.v (netlist).
cd "$(dirname "$0")/.."
B=build/synth; mkdir -p $B
yosys -q -p "read_verilog -sv rtl/connect4.sv; synth -top connect4 -flatten; abc -g gates; opt_clean; \
  tee -q -o $B/stat.txt stat; write_verilog -noattr $B/connect4.v" > $B/yosys.log 2>&1 < /dev/null \
  || { echo "yosys failed (see $B/yosys.log)"; exit 1; }
awk '/^ +\$_/ { c=$1; v=$2; if (c ~ /DFF/) ff+=v; else if (c=="$_NOT_") inv+=v; else g+=v }
  END { printf "connect4 (6 x 7): %d flip-flops, %d two-input gates, %d inverters, %d cells\n", ff, g, inv, ff+g+inv }' \
  $B/stat.txt | tee $B/summary.txt
