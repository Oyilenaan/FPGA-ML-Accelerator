// =============================================================================
// relu.v — Parameterised ReLU Activation with Output Saturation
// -----------------------------------------------------------------------------
// Takes a signed accumulator value and:
//   1. Clamps negative values to 0          (ReLU)
//   2. Saturates to OUT_WIDTH max if needed  (prevents silent overflow)
//
// IN_WIDTH  : width of the accumulator input (signed, default 20-bit)
// OUT_WIDTH : width of the output pixel      (unsigned, default 8-bit)
// =============================================================================
module relu #(
  parameter IN_WIDTH  = 20,
  parameter OUT_WIDTH = 8
)(
  input  wire                  clk,
  input  wire                  rst_n,
  input  wire                  valid_in,
  input  wire [IN_WIDTH-1:0]   data_in,    // treated as signed
  output reg  [OUT_WIDTH-1:0]  data_out,
  output reg                   valid_out
);

  localparam signed [IN_WIDTH-1:0]  ZERO    = 0;
  localparam        [IN_WIDTH-1:0]  SAT_MAX = (1 << OUT_WIDTH) - 1;

  wire signed [IN_WIDTH-1:0] data_signed = $signed(data_in);

  always @(posedge clk) begin
    if (!rst_n) begin
      data_out  <= 0;
      valid_out <= 0;
    end else begin
      valid_out <= valid_in;
      if (data_signed <= ZERO)
        data_out <= 0;                          // ReLU clamp
      else if (data_in > SAT_MAX)
        data_out <= {OUT_WIDTH{1'b1}};          // saturate to max
      else
        data_out <= data_in[OUT_WIDTH-1:0];     // pass through
    end
  end

endmodule
