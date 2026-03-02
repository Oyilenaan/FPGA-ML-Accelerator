// =============================================================================
// conv3x3.v — 3×3 Convolution Engine
// -----------------------------------------------------------------------------
// Streams 9 pixel/weight pairs into the MAC PE one per clock cycle.
// After 9 + pipeline-latency cycles, valid_out pulses with the result.
// Weights are loaded as a flat 72-bit bus [w0..w8], each 8 bits.
// Pixels are loaded as a flat 72-bit bus [p0..p8] (the 3×3 window).
//
// Ports:
//   start_in  — pulse high for 1 cycle to begin a convolution
//   pixels    — 72-bit: 9 × 8-bit pixel values from the sliding window
//   weights   — 72-bit: 9 × 8-bit kernel weights (fixed for a given layer)
//   result    — 20-bit accumulated dot product (before activation)
//   valid_out — pulses high for 1 cycle when result is ready
// =============================================================================
module conv3x3 #(
  parameter DATA_WIDTH = 8,
  parameter ACC_WIDTH  = 20,
  parameter KERNEL_SIZE = 9
)(
  input  wire                    clk,
  input  wire                    rst_n,
  input  wire                    start_in,
  input  wire [KERNEL_SIZE*DATA_WIDTH-1:0] pixels,
  input  wire [KERNEL_SIZE*DATA_WIDTH-1:0] weights,
  output wire [ACC_WIDTH-1:0]    result,
  output wire                    valid_out
);

  // ---- Unpack pixel and weight buses into arrays ----
  wire [DATA_WIDTH-1:0] px [0:KERNEL_SIZE-1];
  wire [DATA_WIDTH-1:0] wt [0:KERNEL_SIZE-1];

  genvar i;
  generate
    for (i = 0; i < KERNEL_SIZE; i = i + 1) begin : unpack
      assign px[i] = pixels [(i+1)*DATA_WIDTH-1 : i*DATA_WIDTH];
      assign wt[i] = weights[(i+1)*DATA_WIDTH-1 : i*DATA_WIDTH];
    end
  endgenerate

  // ---- Step counter: counts 0..8 to serialize the 9 MAC operations ----
  reg [3:0] step;
  reg       running;

  always @(posedge clk) begin
    if (!rst_n) begin
      step    <= 0;
      running <= 0;
    end else begin
      if (start_in) begin
        running <= 1;
        step    <= 0;
      end else if (running) begin
        if (step == KERNEL_SIZE - 1) begin
          running <= 0;
          step    <= 0;
        end else begin
          step <= step + 1;
        end
      end
    end
  end

  // ---- Mux pixel/weight for current step ----
  reg [DATA_WIDTH-1:0] cur_pixel, cur_weight;
  reg                  mac_valid, mac_flush;

  always @(*) begin
    cur_pixel  = px[step];
    cur_weight = wt[step];
    mac_valid  = running;
    mac_flush  = running && (step == 0);
  end

  // ---- Instantiate MAC PE ----
  mac_pe #(
    .DATA_WIDTH(DATA_WIDTH),
    .ACC_WIDTH (ACC_WIDTH)
  ) u_mac (
    .clk       (clk),
    .rst_n     (rst_n),
    .flush     (mac_flush),
    .valid_in  (mac_valid),
    .pixel     (cur_pixel),
    .weight    (cur_weight),
    .acc_out   (result),
    .valid_out (valid_out)
  );

endmodule
