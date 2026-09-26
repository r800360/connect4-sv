# Connect Four game controller in SystemVerilog

A synthesizable, parameterized Connect Four controller: button debouncing and edge detection, gravity, turn-taking,
win detection over every four-in-a-row window, draw detection, and a board lockout at the end of the game.

It is verified three ways:
* a self-checking testbench against a behavioral model;
* **unbounded formal proofs** (ABC PDR/IC3) of seven game invariants;
* **mutation testing** that shows the proofs catch real bugs.

The design started as a two-person schematic project in a university digital-design lab, co-designed with a course
project partner. This repository is a clean re-implementation in SystemVerilog, written after an analysis of that
first version. The analysis found reset, turn-keeping and clocking bugs, one wrong lookup-table entry, and a power-on
race, which is why verification is the focus here.

## Interface

```systemverilog
module connect4 #(ROWS = 6, COLS = 7, WIN = 4, SYNC = 2) (
  input  logic                 clk,
  input  logic                 rst,         // synchronous: empty board, red to move
  input  logic [COLS-1:0]      btn,         // one button per column, asynchronous, active high
  output logic [ROWS*COLS-1:0] red, yellow, // cell (c, r) at bit c*ROWS + r, r = 0 is the bottom row
  output logic                 turn,        // 0: red to move, 1: yellow to move
  output logic                 win_red, win_yellow, draw, game_over);
```

## Architecture

| Block | Implementation |
|---|---|
| Button input | `SYNC`-stage synchronizer per button, then a rising-edge detector; a press is accepted only if **exactly one** button rose in that cycle |
| Legality | `move[c] = one_press & press[c] & ~game_over & (height[c] != ROWS)` |
| Board | per column, a `$clog2(ROWS+1)`-bit height and `ROWS` color bits; a cell is occupied when `row < height` |
| Turn | toggles only on an accepted move, cleared by reset |
| Win | `four()` checks every horizontal, vertical and diagonal window of `WIN` cells (69 windows for 6 × 7 / 4) |
| Draw / game over | all columns full without a win; `game_over` blocks every move until reset |

Because the board only ever gains tokens and freezes once the game is over, a win can never disappear. There are no
derived clocks: every register is on `clk`.

## Verification

### Simulation: `make sim` (Icarus Verilog and Verilator)

`tb/tb_connect4.sv` drives the DUT with button presses and compares, after every press, all 42 cells and the turn,
win, draw and game-over outputs with an independent behavioral model.

| Category | Tests |
|---|---|
| FUNC | 15 directed games, each machine-checked by `scripts/c4model.py` to end in a specific first win: vertical (rows 1–4, 2–5, 3–6), horizontal (bottom and upper rows), both diagonals, both colors. Also a 42-move draw, a near-win that must *not* count, and 300 random games played to the first win |
| ROBUST | presses on full columns, play after a win, reset mid-game, 19 presses on one column, 100 random 60-press games, win persistence |
| INFO | two buttons in the same cycle (ignored by design) |

Every test can also be run alone (`+TEST=n`).

### Formal: `make formal` (Yosys + ABC PDR + yosys-smtbmc/Z3)

`formal/connect4_formal.sv` states seven invariants as immediate assertions over registered previous-cycle values:

| | Property |
|---|---|
| P1 | #red = #yellow + turn: turns strictly alternate, and no token is lost or duplicated |
| P2 | gravity: no token above an empty cell |
| P3 | red and yellow never win at the same time |
| P4 | once the game is over, the board and the turn never change until reset |
| P5 | a win never disappears until reset |
| P6 | a clock cycle changes at most one cell |
| P7 | one reset cycle gives an empty board with red to move |

**Results:**
* **All seven are proven unbounded** with ABC's PDR on a 4 × 4 board with 3 in a row, in about 5 minutes. The RTL is
  fully parameterized, so the same code is proven. `BIG=1` also attempts 4 × 5 with 4 in a row; that proof did not
  finish within an hour on a laptop.
* The full 6 × 7 board is checked by bounded model checking: no violation in 10 cycles from reset.
* **Mutation check:** four deliberately broken copies of the RTL must each fail the proof, and they do. The mutants
  never toggle the turn, have no game-over lockout, accept simultaneous presses, and ignore full columns.

> Toolchain note: Yosys ≥ 0.30 elaborates `assert` into `$check` cells. Without `async2sync; chformal -lower` before
> `write_smt2`, the SMT model silently contains *no* properties and every check "passes". The scripts count the
> assertions in the generated model and stop if there are none.

### Synthesis: `make synth`

`yosys synth -flatten` followed by `abc -g gates` maps the default 6 × 7 configuration to a generic gate library.
The result is written to `build/synth_stat.txt`:

| | Cells |
|---|---|
| Flip-flops | 85: 42 color bits, 7 × 3 height bits, the turn, and 7 × 3 button synchronizer / edge-detector stages |
| Two-input gates | 746 (AND/NAND/OR/NOR/ANDNOT/ORNOT/XOR/XNOR) |
| Inverters | 9 |
| **Total** | **840** |

## Repository layout

```
rtl/connect4.sv              the design
tb/tb_connect4.sv            self-checking testbench (+ tb_common.svh, directed_games.svh)
formal/connect4_formal.sv    properties; pdr.sh (one PDR proof), run_formal.sh (campaign incl. mutants and BMC)
scripts/c4model.py           Python reference model; searches the directed games
Makefile                     lint / sim / formal / synth
```

## Running

```bash
make lint sim        # Verilator lint, Icarus and Verilator simulation
make formal          # PDR proofs, mutation check, bounded model check
make synth           # Yosys gate count
```
