#!/bin/bash
# run_formal.sh - formal campaign for rtl/connect4.sv (Yosys + ABC PDR + yosys-smtbmc/Z3). Summary: build/formal/summary.txt
#   1. unbounded proofs (ABC PDR / IC3) of every assertion of connect4_formal.sv on reduced boards
#   2. mutation check: four deliberately broken copies of the RTL must each FAIL the same proof
#   3. bounded model check of the full 6 x 7 board
cd "$(dirname "$0")"
OUTD=../build/formal; mkdir -p $OUTD/mutants
OUT=$OUTD/summary.txt; : > $OUT
log() { echo "$@" | tee -a $OUT; }
log "== unbounded proofs (ABC PDR); the RTL is parameterised, the same code is used for 6 x 7"
log "$(R=4 C=4 W=3 TO=${TO_SMALL:-1800} bash pdr.sh 2>/dev/null | grep -E 'PROVED|FAILED|TIMEOUT|UNKNOWN')"
[ -n "${BIG:-}" ] && log "$(R=4 C=5 W=4 TO=${TO_BIG:-7200} bash pdr.sh 2>/dev/null | grep -E 'PROVED|FAILED|TIMEOUT|UNKNOWN')"
log "== mutation check (4 x 4 board, 3 in a row): every mutant must FAIL"
mk() { sed "$2" ../rtl/connect4.sv > $OUTD/mutants/$1.sv; grep -q "$3" $OUTD/mutants/$1.sv || log "   (mutation $1 did not apply)"; }
mk no_toggle     's/turn <= ~turn;/turn <= turn;/'                                            'turn <= turn;'
mk no_lockout    's/press\[c\] \&\& !game_over \&\&/press[c] \&\&/'                             'press\[c\] && (height'
mk multi_press   's/assign move\[c\] = one_press \&\& press\[c\]/assign move[c] = press[c]/'    'assign move\[c\] = press\[c\]'
mk no_full_check 's/ \&\& (height\[c\] != HW'"'"'(ROWS));/;/'                                  'game_over;'
for m in no_toggle no_lockout multi_press no_full_check; do
  log "   $(RTL=$OUTD/mutants/$m.sv TAG=$m R=4 C=4 W=3 TO=900 bash pdr.sh 2>/dev/null | grep -E 'PROVED|FAILED|TIMEOUT|UNKNOWN')"
done
log "== bounded model check, full 6 x 7 board, ${DEPTH:-10} cycles from reset (yosys-smtbmc + z3)"
yosys -q -l $OUTD/bmc.yosys.log -p "read_verilog -sv -formal -DFORMAL ../rtl/connect4.sv connect4_formal.sv; \
  prep -top connect4_formal; flatten; async2sync; chformal -lower; opt -fast; dffunmap; write_smt2 -wires $OUTD/full.smt2"
log "   model: $(grep -c yosys-smt2-assert $OUTD/full.smt2) assertions"
timeout 7200 yosys-smtbmc -s z3 --presat -t ${DEPTH:-10} $OUTD/full.smt2 > $OUTD/bmc.log 2>&1
log "   $(grep -aoE 'Status: [A-Z]+' $OUTD/bmc.log | tail -1)"
