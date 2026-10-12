#!/bin/bash
# run_formal.sh - formal campaign for rtl/connect4.sv. Every line states its expected outcome; the script exits 1 if
# any outcome differs. Summary: build/formal/summary.txt
#   1. unbounded proof (ABC PDR) of every assertion of connect4_formal.sv on a 4 x 4 board, 3 in a row; the RTL is
#      parameterized, so this is the same code as the 6 x 7 game (BIG=1 also tries 4 x 5 with 4 in a row, which did
#      not finish within an hour on a laptop, so its outcome is only reported)
#   2. mutation check: four broken copies of the RTL must each fail that proof
#   3. bounded model check of the full 6 x 7 board, DEPTH (default 10) cycles from reset (skipped with QUICK=1)
cd "$(dirname "$0")"
OUTD=../build/formal; mkdir -p $OUTD/mutants
OUT=$OUTD/summary.txt; : > $OUT
bad=0
log() { echo "$@" | tee -a $OUT; }
expect() {  # expected-word result-line
  local got=${2#*: }; got=${got%% *}
  if [ "$got" = "$1" ]; then log "  ok        $2"; else log "  UNEXPECTED (expected $1) $2"; bad=1; fi
}
pdr() { bash pdr.sh 2>/dev/null | grep -E 'PROVED|FAILED|TIMEOUT|UNKNOWN|ERROR'; }

log "== unbounded proof (ABC PDR), 4 x 4 board, 3 in a row"
expect PROVED "$(R=4 C=4 W=3 TO=${TO_SMALL:-5400} pdr)"
[ -n "${BIG:-}" ] && log "  info      $(R=4 C=5 W=4 TO=${TO_BIG:-7200} pdr)"

log "== mutation check: every mutant must FAIL"
mk() {  # name sed-expression text-that-proves-it-applied
  sed "$2" ../rtl/connect4.sv > $OUTD/mutants/$1.sv
  grep -q "$3" $OUTD/mutants/$1.sv || { log "  mutation $1 did not apply"; bad=1; }
}
mk no_toggle     's/turn <= ~turn;/turn <= turn;/'                                            'turn <= turn;'
mk no_lockout    's/press\[c\] \&\& !game_over \&\&/press[c] \&\&/'                             'press\[c\] && (height'
mk multi_press   's/assign move\[c\] = one_press \&\& press\[c\]/assign move[c] = press[c]/'    'assign move\[c\] = press\[c\]'
mk no_full_check 's/ \&\& (height\[c\] != HW'"'"'(ROWS));/;/'                                  'game_over;'
for m in no_toggle no_lockout multi_press no_full_check; do
  expect FAILED "$(RTL=$OUTD/mutants/$m.sv TAG=$m R=4 C=4 W=3 TO=900 pdr)"
done

if [ -z "${QUICK:-}" ]; then
  log "== bounded model check, full 6 x 7 board, ${DEPTH:-10} cycles from reset (yosys-smtbmc + Z3)"
  yosys -q -l $OUTD/bmc.yosys.log -p "read_verilog -sv -formal -DFORMAL ../rtl/connect4.sv connect4_formal.sv; \
    prep -top connect4_formal; flatten; async2sync; chformal -lower; opt -fast; dffunmap; write_smt2 -wires $OUTD/full.smt2"
  n=$(grep -c yosys-smt2-assert $OUTD/full.smt2)
  start=$(date +%s)
  timeout 7200 yosys-smtbmc -s z3 --presat -t ${DEPTH:-10} $OUTD/full.smt2 > $OUTD/bmc.log 2>&1
  status=$(grep -aoE 'Status: [A-Z]+' $OUTD/bmc.log | tail -1 | cut -d' ' -f2)
  expect PASSED "full_board_bmc: ${status:-ERROR} ($n assertions, ${DEPTH:-10} cycles) in $(( $(date +%s) - start ))s"
fi

if [ $bad -eq 0 ]; then log "ALL OUTCOMES AS EXPECTED"; else log "SOME OUTCOMES UNEXPECTED"; fi
exit $bad
