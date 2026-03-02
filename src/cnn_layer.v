// =============================================================================
// cnn_layer.v — Top-Level CNN Layer (Conv3×3 + ReLU)
// -----------------------------------------------------------------------------
// Integrates the conv3x3 engine and relu activation into a single module
// with clean valid/ready handshaking.
//
// Interface:
//   valid_in  — assert for 1 cycle alongside pixels/weights to start
//   ready_out — high when the module can accept a new input
//   pixels    — 72-bit: 9 × 8-bit pixel window (row-major, top-left first)
//   weights   — 72-bit: 9 × 8-bit kernel weights
//   result    — 8-bit ReLU-activated output
//   valid_out — pulses high for 1 cycle when result is ready
//
// Latency: 9 (serialise) + 3 (MAC pipeline) + 1 (ReLU) = 13 clock cycles
// =============================================================================
module cnn_layer #(
  parameter DATA_WIDTH  = 8,
  parameter ACC_WIDTH   = 20,
  parameter KERNEL_SIZE = 9
)(
  input  wire                              clk,
  input  wire                              rst_n,      // active-low sync reset

  // Input handshake
  input  wire                              valid_in,
  output wire                              ready_out,

  // Data
  input  wire [KERNEL_SIZE*DATA_WIDTH-1:0] pixels,
  input  wire [KERNEL_SIZE*DATA_WIDTH-1:0] weights,

  // Output
  output wire [DATA_WIDTH-1:0]             result,
  output wire                              valid_out
);

  // ---- Internal wires ----
  wire [ACC_WIDTH-1:0] conv_result;
  wire                 conv_valid;

  // ---- Ready: not busy (simple version — can be pipelined further) ----
  reg busy;
  assign ready_out = !busy;

  always @(posedge clk) begin
    if (!rst_n)
      busy <= 0;
    else if (valid_in && ready_out)
      busy <= 1;
    else if (conv_valid)
      busy <= 0;
  end

  // ---- Convolution engine ----
  conv3x3 #(
    .DATA_WIDTH (DATA_WIDTH),
    .ACC_WIDTH  (ACC_WIDTH),
    .KERNEL_SIZE(KERNEL_SIZE)
  ) u_conv (
    .clk      (clk),
    .rst_n    (rst_n),
    .start_in (valid_in && ready_out),
    .pixels   (pixels),
    .weights  (weights),
    .result   (conv_result),
    .valid_out(conv_valid)
  );

  // ---- ReLU activation ----
  relu #(
    .IN_WIDTH (ACC_WIDTH),
    .OUT_WIDTH(DATA_WIDTH)
  ) u_relu (
    .clk      (clk),
    .rst_n    (rst_n),
    .valid_in (conv_valid),
    .data_in  (conv_result),
    .data_out (result),
    .valid_out(valid_out)
  );

endmodule
