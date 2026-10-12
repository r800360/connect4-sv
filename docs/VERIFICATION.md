# Verification

`make ci` runs on every push; `make full` adds the full-board bounded model check. Logs and reports go to `build/`,
and `build/SUMMARY.md` collects them.

## Simulation (`make sim`)

`tb/tb_connect4.sv` presses buttons the way a player would: each press is held for 3 cycles and then released for 3,
which covers the synchronizer. After every press, it compares all 42 cells, the turn, and the win, draw and game-over
flags with an independent behavioral model of the board.

| Category | Tests |
|---|---|
| FUNC | 15 directed games. 13 end in a specific first win, each found and machine-checked by `scripts/c4model.py`: vertical (rows 1–4, 2–5, 3–6), horizontal (bottom row and row 4 or higher), both diagonal directions, both colors. One is a 42-move draw, and one is a near-win that must *not* count. Then 300 random games played to the first win |
| ROBUST | presses on full columns, play after a win, reset mid-game, 19 presses on one column, 100 random 60-press games, win persistence |
| INFO | two buttons in the same cycle (reported, not counted: the design ignores such presses) |

`+TEST=n` runs a single test. Random games use the fixed-seed xorshift generator in `tb/tb_common.svh`, so both
simulators see the same games.

## Formal (`make formal`)

`formal/connect4_formal.sv` states the seven invariants of the README as immediate assertions. It compares current
values with explicitly registered previous-cycle values; the first cycle is a reset. `formal/run_formal.sh` runs:

1. **Unbounded proof** of all seven properties with ABC's PDR, on a 4 × 4 board with 3 in a row (about 5 minutes).
   `BIG=1` also tries 4 × 5 with 4 in a row; it did not finish within an hour on a laptop, so it is only reported.
2. **Mutation check.** Four broken copies of the RTL must each fail the same proof:
   * the turn never toggles;
   * no game-over lockout;
   * simultaneous presses are accepted;
   * full columns are not checked.
3. **Bounded model check** of the full 6 × 7 board for 10 cycles from reset, with yosys-smtbmc and Z3 (skipped by
   `make formal-quick`).

Every step states its expected outcome, and the script exits non-zero if any outcome differs.

## Tools and how they are run

| Tool (version) | Used for | Command |
|---|---|---|
| Icarus Verilog 12.0 | simulation | `iverilog -g2012 -I tb -o build/connect4.vvp tb/tb_connect4.sv rtl/connect4.sv`, then `vvp -n build/connect4.vvp` |
| Verilator 5.032 | lint, compiled simulation | `verilator --lint-only -Wall --top-module connect4 rtl/connect4.sv`; `verilator --binary --timing -O2 -Itb --top-module tb_connect4 ...` |
| Yosys 0.52 + ABC | synthesis, PDR proofs | `formal/pdr.sh`: Yosys writes an AIGER model of the harness, then `yosys-abc -c "read_aiger m.aig; fold; strash; pdr"` |
| yosys-smtbmc + Z3 4.13 | full-board BMC | Yosys `write_smt2`, then `yosys-smtbmc -s z3 --presat -t 10 full.smt2` |
| Python 3 | game model and directed-game search | `python3 scripts/c4model.py tb/directed_games.svh` |

The Yosys script for the proof model, step by step:

```
read_verilog -sv -formal -DFORMAL rtl/connect4.sv formal/connect4_formal.sv
chparam -set R 4 -set C 4 -set W 3 connect4_formal
prep -top connect4_formal; flatten; async2sync
chformal -lower                  # turn $check cells into $assert / $assume
chformal -assume -early; chformal -cover -remove
opt_clean; setundef -anyseq; opt -keepdc -fast; techmap; opt -fast; dffunmap; abc -g AND -fast; opt_clean
write_aiger -I -B -zinit m.aig   # assertions become bad-state properties
```

**Pitfalls:**
* **Vacuous checks.** Yosys 0.52 elaborates `assert` into `$check` cells. Without `chformal -lower`, the model contains
  no properties and every check passes vacuously. The scripts count the properties in the model and refuse to run on
  none.
* **Assertion timing.** Clocked concurrent assertions are sampled a cycle late in this flow, and hierarchical
  references into the DUT are not supported. Hence the immediate assertions over registered history in the harness.
* **Z3 induction.** k-induction on the full board did not converge in our runs. PDR on the parameterized smaller
  board gives the unbounded result instead.

## CI

| Workflow | Trigger | Runs |
|---|---|---|
| CI (`.github/workflows/ci.yml`) | every push to `main`, pull requests | `lint`, `sim`, `formal-quick`, `synth` |
| Full verification (`full.yml`) | manual, or a `v*` tag | the CI steps, with the full `formal` campaign in place of `formal-quick`; a tag also publishes a release |

Both run in the pinned `ubuntu:26.04` image, installed by `scripts/install-tools.sh`, the same script as the
`Dockerfile`. `build/` is uploaded as an artifact, without object files.
