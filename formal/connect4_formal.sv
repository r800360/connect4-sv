// connect4_formal.sv - formal properties of connect4 (Yosys read_verilog -formal + yosys-smtbmc + z3).
//
// Proven by k-induction for every reachable state and every button sequence:
//   P1  token count  : #red == #yellow + turn          (turns strictly alternate, nothing is lost or duplicated)
//   P2  gravity      : no cell is occupied above an empty cell
//   P3  one winner   : red and yellow never win at the same time
//   P4  frozen board : once the game is over the board and the turn do not change until reset
//   P5  persistence  : a win never disappears until reset
//   P6  one token    : a clock cycle changes at most one cell
//   P7  reset        : one reset cycle gives an empty board with red to move
// Covers show that a red win and a yellow win are reachable.
//
// All assertions are immediate (always_comb) over explicitly registered previous values, so every check refers to
// exactly one step of the model (assertions inside clocked blocks are sampled one cycle late by Yosys, which makes
// the induction step needlessly deep).
module connect4_formal #(
  parameter int R = 6,                     // rows    (the proofs also run on reduced boards, see pdr.sh)
  parameter int C = 7,                     // columns
  parameter int W = 4                      // cells in a row needed to win
) (
  input logic         clk,
  input logic         rst,
  input logic [C-1:0] btn
);
  localparam int N = R * C;
  logic [N-1:0] red, yellow;
  logic turn, win_red, win_yellow, draw, game_over;

  connect4 #(.ROWS(R), .COLS(C), .WIN(W), .SYNC(0)) dut (
    .clk, .rst, .btn, .red, .yellow, .turn, .win_red, .win_yellow, .draw, .game_over);

  function automatic logic [5:0] ones(input logic [N-1:0] v);
    logic [5:0] n;
    n = '0;
    for (int i = 0; i < N; i++) n = n + {5'd0, v[i]};
    ones = n;
  endfunction

  // previous-cycle copies
  logic         pv = 1'b0;                 // a previous cycle exists
  logic         p_rst, p_turn, p_over, p_wr, p_wy;
  logic [N-1:0] p_red, p_yel;
  always_ff @(posedge clk) begin
    pv <= 1'b1;
    p_rst <= rst; p_turn <= turn; p_over <= game_over; p_wr <= win_red; p_wy <= win_yellow;
    p_red <= red; p_yel <= yellow;
  end
  always_comb if (!pv) assume (rst);       // the first cycle resets the game

  always_comb if (pv) begin
    if (p_rst) begin
      assert (red == '0 && yellow == '0 && !turn);                                             // P7
    end else begin
      assert (ones(red) == ones(yellow) + {5'd0, turn});                                       // P1
      for (int c = 0; c < C; c++)
        for (int r = 0; r < R - 1; r++)
          assert (!(red[c*R + r + 1] | yellow[c*R + r + 1]) || (red[c*R + r] | yellow[c*R + r])); // P2
      assert (!(win_red && win_yellow));                                                       // P3
      assert ((red & yellow) == '0);
      if (p_over) assert (red == p_red && yellow == p_yel && turn == p_turn);                  // P4
      if (p_wr) assert (win_red);                                                              // P5
      if (p_wy) assert (win_yellow);
      assert (ones((red ^ p_red) | (yellow ^ p_yel)) <= 6'd1);                                 // P6
    end
  end

  always_comb if (pv) begin
    cover (win_red);
    cover (win_yellow);
  end
endmodule
