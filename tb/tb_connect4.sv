// tb_connect4.sv - self-checking testbench for rtl/connect4.sv.
//
// A behavioural model (6 x 7 board, gravity, alternating turns starting with red, four in a row in any of the 69
// windows, no moves after a win) is updated with every button press; after every press the DUT's 42 cells, its turn,
// win and draw outputs are compared with the model.
//
//   FUNC    directed games that end in each kind of win (and a full-board draw), 300 random games to the first win
//   ROBUST  full columns, play after a win, reset mid-game, long random games that ignore the rules
//   INFO    two buttons pressed in the same clock cycle (outside the intended use; the design ignores it)
//
// +TEST=n runs only test n (0 power-on, 1..15 directed, 1000.. random games, 201..206 robust, 301 info).
`timescale 1ns/10ps
`include "tb_common.svh"

module tb_connect4;
  localparam int ROWS = 6, COLS = 7;
  logic clk = 1'b0, rst = 1'b0;
  logic [COLS:1] col = '0;                         // col[k] = button of column k (1 = leftmost)
  logic [ROWS*COLS-1:0] red, yellow;
  logic turn, win_red, win_yellow, draw, game_over;

  connect4 #(.ROWS(ROWS), .COLS(COLS), .SYNC(2)) dut (
    .clk, .rst, .btn(col[COLS:1]), .red, .yellow, .turn, .win_red, .win_yellow, .draw, .game_over);

  task automatic tick(); #5 clk = 1'b1; #5 clk = 1'b0; endtask
  // a press is held for 3 clocks and released for 3 (covers the 2-stage button synchroniser)
  task automatic hw_press(input int k); col[k] = 1'b1; repeat (3) tick(); col[k] = 1'b0; repeat (3) tick(); endtask
  task automatic hw_press2(input int a, input int b);
    col[a] = 1'b1; col[b] = 1'b1; repeat (3) tick(); col = '0; repeat (3) tick();
  endtask
  task automatic hw_reset(); rst = 1'b1; repeat (2) tick(); rst = 1'b0; repeat (3) tick(); endtask

  function automatic int dut_cell(input int c, input int r);      // 0 empty, 1 red, 2 yellow, 3 invalid
    int i;
    i = (c - 1) * ROWS + (r - 1);
    case ({red[i], yellow[i]})
      2'b00: return 0;
      2'b10: return 1;
      2'b01: return 2;
      default: return 3;
    endcase
  endfunction
  function automatic int dut_winner();
    if (win_red && !win_yellow) return 1;
    if (!win_red && win_yellow) return 2;
    if (!win_red && !win_yellow) return 0;
    return 3;
  endfunction

  // ---------------------------------------------------------------- reference model
  int board [1:COLS][1:ROWS];
  int height [1:COLS];
  int mturn, winner, moves;
  task automatic m_reset();
    for (int c = 1; c <= COLS; c++) begin
      height[c] = 0;
      for (int r = 1; r <= ROWS; r++) board[c][r] = 0;
    end
    mturn = 1; winner = 0; moves = 0;
  endtask
  function automatic bit four(input int p);
    bit f;
    f = 0;
    for (int c = 1; c <= COLS; c++)
      for (int r = 1; r <= ROWS; r++) begin
        if (c <= COLS - 3)
          if (board[c][r] == p && board[c+1][r] == p && board[c+2][r] == p && board[c+3][r] == p) f = 1;
        if (r <= ROWS - 3)
          if (board[c][r] == p && board[c][r+1] == p && board[c][r+2] == p && board[c][r+3] == p) f = 1;
        if (c <= COLS - 3 && r <= ROWS - 3)
          if (board[c][r] == p && board[c+1][r+1] == p && board[c+2][r+2] == p && board[c+3][r+3] == p) f = 1;
        if (c <= COLS - 3 && r >= 4)
          if (board[c][r] == p && board[c+1][r-1] == p && board[c+2][r-2] == p && board[c+3][r-3] == p) f = 1;
      end
    return f;
  endfunction
  task automatic m_press(input int k);
    if (winner == 0 && height[k] < ROWS) begin
      height[k]++;
      board[k][height[k]] = mturn;
      moves++;
      if (four(mturn)) winner = mturn;
      mturn = 3 - mturn;
    end
  endtask

  // ---------------------------------------------------------------- comparison
  int errs;
  string first_err;
  function automatic string cellch(input int v, input bit is_dut);
    if (v == 0) return ".";
    if (v == 1) return is_dut ? "r" : "R";
    if (v == 2) return is_dut ? "y" : "Y";
    return "?";
  endfunction
  function automatic string board_str();
    string s, line, x;
    s = "";
    for (int r = ROWS; r >= 1; r--) begin
      line = "";
      for (int c = 1; c <= COLS; c++) begin
        int d, m;
        d = dut_cell(c, r); m = board[c][r];
        if (d == m) x = " "; else x = cellch(d, 1);
        line = $sformatf("%s%s%s", line, cellch(m, 0), x);
      end
      s = $sformatf("%s\n      %s", s, line);
    end
    return s;
  endfunction
  task automatic compare(input string what);
    int bad;
    bad = 0;
    for (int c = 1; c <= COLS; c++) for (int r = 1; r <= ROWS; r++) if (dut_cell(c, r) != board[c][r]) bad++;
    if (dut_winner() != winner) bad += 100;
    if (draw !== (winner == 0 && moves == ROWS * COLS)) bad += 100;
    if (game_over !== (winner != 0 || moves == ROWS * COLS)) bad += 100;
    if (turn !== (mturn == 2) && winner == 0) bad += 1000;
    if (bad) begin
      errs++;
      if (errs == 1)
        first_err = $sformatf("%s: %0d cell(s) differ%s%s (model winner %0d, DUT %0d). Model letter, DUT letter if different:%s",
                              what, bad % 100, (bad % 1000) >= 100 ? ", win/draw/over differs" : "",
                              bad >= 1000 ? ", turn differs" : "", winner, dut_winner(), board_str());
    end
  endtask
  task automatic press(input int k, input string what = "");
    hw_press(k); m_press(k); compare($sformatf("%s press column %0d (move %0d)", what, k, moves));
  endtask
  task automatic new_game(); hw_reset(); m_reset(); compare("after reset"); endtask
  task automatic play(input bit [255:0] d, input int n, input string what);
    // one hex digit per move (column 1..7), first move in the most significant used digit
    for (int i = n - 1; i >= 0; i--) press(int'(d[i * 4 +: 4]), what);
  endtask
  task automatic group(input string cat, input string name);
    `CHECK(cat, name, errs == 0, first_err)
    errs = 0; first_err = "";
  endtask

  // ---------------------------------------------------------------- tests
  int sel;
  task automatic begin_test(); if (sel == -1) new_game(); endtask
`define DIRECTED(N, MV, LEN, NAME) \
    if (sel == -1 || sel == N) begin begin_test(); play(MV, LEN, NAME); group("FUNC", NAME); end
  int ngames, nwins[0:2];
  initial begin
    errs = 0;
    if (!$value$plusargs("TEST=%d", sel)) sel = -1;
    m_reset();
    hw_reset();
    if (sel <= 0) begin compare("power-on"); group("FUNC", "reset: empty board, red to move"); end

    // directed games (scripts/c4model.py: each game verified to end with the named first win)
`include "directed_games.svh"

    ngames = 0; nwins[0] = 0; nwins[1] = 0; nwins[2] = 0;
    for (int g = 0; g < 300; g++) if (sel == -1 || sel == 1000 + g) begin
      begin_test();
      tb_rng_state = 32'd4444 + g * 7919;
      while (winner == 0 && moves < ROWS * COLS) begin
        int k;
        do k = 1 + (tb_rand() % COLS); while (height[k] == ROWS);
        press(k, $sformatf("game %0d", g));
      end
      ngames++; nwins[winner]++;
      if (sel != -1) group("FUNC", $sformatf("random game %0d up to its first win", g));
    end
    if (sel == -1)
      group("FUNC", $sformatf("%0d random games up to the first win (%0d red wins, %0d yellow wins, %0d draws)",
                              ngames, nwins[1], nwins[2], nwins[0]));

    if (sel == -1 || sel == 201) begin
      begin_test(); play(256'h111111, 6, "fill column 1"); play(256'h1, 1, "full column");
      play(256'h2, 1, "next move after full column");
      group("ROBUST", "a press on a full column is ignored (the turn is not lost)");
    end
    if (sel == -1 || sel == 202) begin
      begin_test(); play(256'h1212121, 7, "red wins"); play(256'h1, 1, "move after win");
      play(256'h3456, 4, "more moves after win");
      group("ROBUST", "after a win the board is frozen and the win stays displayed");
    end
    if (sel == -1 || sel == 203) begin
      begin_test(); play(256'h1111, 4, "first game"); play(256'h234, 3, "first game"); new_game();
      play(256'h1, 1, "second game"); play(256'h1111, 4, "second game");
      group("ROBUST", "reset mid-game: empty board, red starts, column heights restart");
    end
    if (sel == -1 || sel == 204) begin
      begin_test(); play(256'h1111111111111111111, 19, "19 presses on column 1");
      group("ROBUST", "many presses on a full column never change the board");
    end
    if (sel == -1 || sel == 205) begin
      tb_rng_state = 32'd99;
      for (int g = 0; g < 100; g++) begin
        if (sel == -1 || g > 0) new_game(); else m_reset();
        for (int i = 0; i < 60; i++) press(1 + (tb_rand() % COLS), $sformatf("long game %0d", g));
      end
      group("ROBUST", "100 random 60-press games (full columns and play after a win included)");
    end
    if (sel == -1 || sel == 206) begin
      begin_test(); play(256'h1212121, 7, "red vertical four");
      for (int i = 0; i < 2; i++) begin
        hw_press(1);
        if (dut_winner() != winner) begin
          errs++;
          if (errs == 1) first_err = $sformatf("after %0d more press(es) the win indication is %0d (expected %0d)",
                                               i + 1, dut_winner(), winner);
        end
      end
      group("ROBUST", "a win stays displayed when more buttons are pressed on top of a vertical four");
    end
    if (sel == -1 || sel == 301) begin
      begin_test(); hw_press2(1, 2); compare("two buttons at once"); play(256'h3, 1, "after double press");
      group("INFO", "two buttons pressed in the same cycle are ignored");
    end
    `REPORT
    $finish;
  end
endmodule
