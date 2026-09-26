// connect4.sv - two-player Connect 4 game controller.
//
// One clock domain. Each column button goes through a SYNC-stage synchroniser and a rising-edge detector; a move is
// accepted when exactly one button rose in the cycle, the column is not full and the game is not over. The board
// is kept as a height counter plus one colour bit per cell for every column, win detection checks every window of
// four cells, and a finished game freezes the board until the synchronous reset.
//
// Cell (c, r) - column c (0 = leftmost), row r (0 = bottom) - is reported at index c*ROWS + r of red / yellow.
module connect4 #(
  parameter int ROWS = 6,
  parameter int COLS = 7,
  parameter int WIN  = 4,
  parameter int SYNC = 2          // button synchroniser stages (0 = inputs already synchronous)
) (
  input  logic                   clk,
  input  logic                   rst,        // synchronous, active high: empty board, red to move
  input  logic [COLS-1:0]        btn,        // column buttons, active high, any timing
  output logic [ROWS*COLS-1:0]   red,
  output logic [ROWS*COLS-1:0]   yellow,
  output logic                   turn,       // 0: red to move, 1: yellow to move
  output logic                   win_red,
  output logic                   win_yellow,
  output logic                   draw,
  output logic                   game_over
);
  localparam int HW = $clog2(ROWS + 1);

  // ---------------------------------------------------------------- button synchroniser + edge detector
  logic [COLS-1:0] btn_s, btn_q, press;
  if (SYNC == 0) begin : g_nosync
    assign btn_s = btn;
  end else begin : g_sync
    logic [COLS-1:0] stage [SYNC];
    always_ff @(posedge clk) begin
      stage[0] <= btn;
      for (int i = 1; i < SYNC; i++) stage[i] <= stage[i-1];
    end
    assign btn_s = stage[SYNC-1];
  end
  always_ff @(posedge clk) btn_q <= btn_s;
  assign press = btn_s & ~btn_q;

  logic one_press;                                   // exactly one button rose this cycle
  assign one_press = (press != '0) && ((press & (press - 1'b1)) == '0);

  // ---------------------------------------------------------------- board state
  logic [HW-1:0]   height [COLS];
  logic [ROWS-1:0] colour [COLS];                    // 1 = yellow, meaningful below height only
  logic [COLS-1:0] move;

  for (genvar c = 0; c < COLS; c++) begin : g_col
    assign move[c] = one_press && press[c] && !game_over && (height[c] != HW'(ROWS));
    always_ff @(posedge clk) begin
      if (rst) begin
        height[c] <= '0;
        colour[c] <= '0;
      end else if (move[c]) begin
        colour[c][height[c]] <= turn;
        height[c]            <= height[c] + 1'b1;
      end
    end
    for (genvar r = 0; r < ROWS; r++) begin : g_cell
      logic occupied;
      assign occupied               = height[c] > HW'(r);
      assign red[c*ROWS + r]        = occupied && !colour[c][r];
      assign yellow[c*ROWS + r]     = occupied &&  colour[c][r];
    end
  end

  always_ff @(posedge clk) begin
    if (rst)         turn <= 1'b0;
    else if (|move)  turn <= ~turn;
  end

  // ---------------------------------------------------------------- win / draw detection
  // 1 if some window of WIN cells in a row, column or diagonal is all set in b
  function automatic logic four(input logic [ROWS*COLS-1:0] b);
    logic f, h, v, d, a;
    f = 1'b0;
    for (int c = 0; c < COLS; c++) begin
      for (int r = 0; r < ROWS; r++) begin
        h = 1'b1; v = 1'b1; d = 1'b1; a = 1'b1;
        for (int i = 0; i < WIN; i++) begin
          if (c <= COLS - WIN)                       h = h & b[(c + i) * ROWS + r];
          if (r <= ROWS - WIN)                       v = v & b[c * ROWS + r + i];
          if (c <= COLS - WIN && r <= ROWS - WIN)    d = d & b[(c + i) * ROWS + r + i];
          if (c <= COLS - WIN && r >= WIN - 1)       a = a & b[(c + i) * ROWS + r - i];
        end
        f = f | (h && c <= COLS - WIN) | (v && r <= ROWS - WIN) |
                (d && c <= COLS - WIN && r <= ROWS - WIN) | (a && c <= COLS - WIN && r >= WIN - 1);
      end
    end
    four = f;                                        // (not "return": Yosys 0.52 needs the classic form)
  endfunction

  logic full;
  always_comb begin
    full = 1'b1;
    for (int c = 0; c < COLS; c++) full &= (height[c] == HW'(ROWS));
  end
  assign win_red    = four(red);
  assign win_yellow = four(yellow);
  assign draw       = full && !win_red && !win_yellow;
  assign game_over  = win_red || win_yellow || draw;

`ifdef FORMAL
  // helper invariant for k-induction (formal/connect4_formal.sv): a column never holds more than ROWS tokens
  logic f_valid = 1'b0;                              // registers are arbitrary until the first (reset) clock
  always_ff @(posedge clk) f_valid <= 1'b1;
  always_comb if (f_valid) for (int c = 0; c < COLS; c++) assert (height[c] <= HW'(ROWS));
`endif
endmodule
