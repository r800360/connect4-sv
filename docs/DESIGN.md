# Design

## Interface

```systemverilog
module connect4 #(ROWS = 6, COLS = 7, WIN = 4, SYNC = 2) (
  input  logic                 clk,
  input  logic                 rst,         // synchronous: empty board, red to move
  input  logic [COLS-1:0]      btn,         // one button per column, asynchronous, active high
  output logic [ROWS*COLS-1:0] red, yellow, // cell (c, r) at bit c*ROWS + r; r = 0 is the bottom row
  output logic                 turn,        // 0: red to move, 1: yellow to move
  output logic                 win_red, win_yellow, draw, game_over);
```

## Architecture

| Block | Implementation |
|---|---|
| Button input | `SYNC`-stage synchronizer per button, then a rising-edge detector. A press is accepted only if **exactly one** button rose in that cycle (`press != 0 && (press & (press - 1)) == 0`) |
| Legality | `move[c] = one_press & press[c] & !game_over & (height[c] != ROWS)` |
| Board | per column, a `$clog2(ROWS+1)`-bit height and `ROWS` color bits. A cell is occupied when its row is below the height; its color bit is meaningful only then |
| Turn | toggles only on an accepted move; cleared by reset |
| Win | `four()` checks every horizontal, vertical and diagonal window of `WIN` cells (69 windows for 6 × 7 with 4 in a row) |
| Draw, game over | draw = all columns full without a win. `game_over` = a win or a draw, and it blocks every move until reset |

Every register is on `clk`, and there are no derived clocks. The board only gains tokens and freezes once the game is
over, so a win can never disappear (property P5).

**Parameterization.** All four parameters are free. The proof runs at 4 × 4 with 3 in a row (`ROWS = COLS = 4`,
`WIN = 3`), which elaborates the same RTL as the 6 × 7 game.

## Synthesis (`make synth`)

`yosys synth -flatten; abc -g gates` maps the 6 × 7 configuration to a generic gate library. The statistics and the
netlist are written to `build/synth/`.

| Cells | Count |
|---|---|
| Flip-flops | 85: 42 color bits, 7 × 3 height bits, the turn, and 7 × 3 synchronizer and edge-detector stages |
| Two-input gates | 746 (AND, NAND, OR, NOR, ANDNOT, ORNOT, XOR, XNOR) |
| Inverters | 9 |
| **Total** | **840** |
