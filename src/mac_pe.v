// =============================================================================
// mac_pe.v — Pipelined Multiply-Accumulate Processing Element
// -----------------------------------------------------------------------------
// 3-stage pipeline: Stage 1 = register inputs, Stage 2 = multiply,
// Stage 3 = accumulate. Accepts a flush signal to reset the accumulator
// between output pixels.
// DATA_WIDTH : input/weight bit width (default 8-bit)
// ACC_WIDTH  : accumulator width, must be >= 2*DATA_WIDTH (default 20-bit)
// =============================================================================
module mac_pe #(
  parameter DATA_WIDTH = 8,
  parameter ACC_WIDTH  = 20
)(
  input  wire                  clk,
  input  wire                  rst_n,       // active-low synchronous reset
  input  wire                  flush,       // clear accumulator (start new pixel)
  input  wire                  valid_in,
  input  wire [DATA_WIDTH-1:0] pixel,
  input  wire [DATA_WIDTH-1:0] weight,
  output reg  [ACC_WIDTH-1:0]  acc_out,
  output reg                   valid_out
);

  // ---- Stage 1: Register inputs ----
  reg [DATA_WIDTH-1:0] s1_pixel, s1_weight;
  reg                  s1_valid, s1_flush;

  always @(posedge clk) begin
    if (!rst_n) begin
      s1_pixel  <= 0;
      s1_weight <= 0;
      s1_valid  <= 0;
      s1_flush  <= 0;
    end else begin
      s1_pixel  <= pixel;
      s1_weight <= weight;
      s1_valid  <= valid_in;
      s1_flush  <= flush;
    end
  end

  // ---- Stage 2: Multiply ----
  reg [2*DATA_WIDTH-1:0] s2_product;
  reg                    s2_valid, s2_flush;

  always @(posedge clk) begin
    if (!rst_n) begin
      s2_product <= 0;
      s2_valid   <= 0;
      s2_flush   <= 0;
    end else begin
      s2_product <= s1_pixel * s1_weight;
      s2_valid   <= s1_valid;
      s2_flush   <= s1_flush;
    end
  end

  // ---- Stage 3: Accumulate ----
  always @(posedge clk) begin
    if (!rst_n) begin
      acc_out   <= 0;
      valid_out <= 0;
    end else begin
      valid_out <= s2_valid;
      if (s2_flush)
        acc_out <= {{(ACC_WIDTH - 2*DATA_WIDTH){1'b0}}, s2_product};
      else if (s2_valid)
        acc_out <= acc_out + {{(ACC_WIDTH - 2*DATA_WIDTH){1'b0}}, s2_product};
    end
  end

endmodule
