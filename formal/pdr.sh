#!/bin/bash
# pdr.sh - unbounded safety proof of every assertion in connect4_formal.sv with ABC's PDR (IC3), the engine
# SymbiYosys calls "abc pdr".
#   R, C, W  board rows / columns / win length (default 6 x 7, 4 in a row)
#   RTL      implementation to prove (default ../rtl/connect4.sv; run_formal.sh passes mutated copies)
#   TO       time limit in seconds
cd "$(dirname "$0")"
OUTD=../build/formal; mkdir -p $OUTD
R=${R:-6}; C=${C:-7}; W=${W:-4}
TAG=${TAG:-c4_${R}x${C}_w${W}}
yosys -q -l $OUTD/$TAG.yosys.log -p "read_verilog -sv -formal -DFORMAL ${RTL:-../rtl/connect4.sv} connect4_formal.sv; \
  chparam -set R $R -set C $C -set W $W connect4_formal; \
  prep -top connect4_formal; flatten; async2sync; chformal -lower; chformal -assume -early; chformal -cover -remove; \
  opt_clean; setundef -anyseq; opt -keepdc -fast; techmap; opt -fast; dffunmap; abc -g AND -fast; opt_clean; \
  write_aiger -I -B -zinit -map $OUTD/$TAG.aim $OUTD/$TAG.aig" || { echo "$TAG: yosys failed"; exit 2; }
start=$(date +%s)
timeout ${TO:-1800} yosys-abc -c "read_aiger $OUTD/$TAG.aig; fold; strash; pdr" > $OUTD/$TAG.pdr.log 2>&1
rc=$?
t=$(( $(date +%s) - start ))
if grep -q "Property proved" $OUTD/$TAG.pdr.log; then
  echo "$TAG: PROVED (all assertions, unbounded) in ${t}s   [$(head -1 $OUTD/$TAG.aig)]"
elif grep -qE "was asserted|Counter-example" $OUTD/$TAG.pdr.log; then
  echo "$TAG: FAILED (counterexample, frame $(grep -oE 'frame [0-9]+' $OUTD/$TAG.pdr.log | head -1 | cut -d' ' -f2)) in ${t}s"
elif [ $rc -eq 124 ]; then
  echo "$TAG: TIMEOUT after ${t}s"
else
  echo "$TAG: UNKNOWN (rc=$rc): $(tail -2 $OUTD/$TAG.pdr.log | tr '\n' ' ')"
fi
