// =============================================================================
// cnn_layer_axis.v — AXI-Stream Wrapper for CNN Layer
// -----------------------------------------------------------------------------
// Input:  18-byte AXI-S packets (9 pixel bytes then 9 weight bytes)
// Output: 1-byte result packet per input packet
// =============================================================================
module cnn_layer_axis #(
  parameter DATA_WIDTH  = 8,
  parameter ACC_WIDTH   = 20,
  parameter KERNEL_SIZE = 9
)(
  input  wire        aclk,
  input  wire        aresetn,

  input  wire [DATA_WIDTH-1:0] s_axis_tdata,
  input  wire                  s_axis_tvalid,
  input  wire                  s_axis_tlast,
  output wire                  s_axis_tready,

  output reg  [DATA_WIDTH-1:0] m_axis_tdata,
  output reg                   m_axis_tvalid,
  output reg                   m_axis_tlast,
  input  wire                  m_axis_tready
);

  localparam TOTAL_BYTES = KERNEL_SIZE * 2; // 18

  // ---- States ----
  localparam S_COLLECT = 2'd0;  // accepting bytes
  localparam S_FIRE    = 2'd1;  // pulsing core valid_in
  localparam S_WAIT    = 2'd2;  // waiting for core to finish

  reg [1:0] state;
  reg [4:0] byte_cnt;

  // ---- Byte buffer ----
  reg [DATA_WIDTH-1:0] buf_r [0:TOTAL_BYTES-1];

  // ---- Only accept bytes in COLLECT state ----
  assign s_axis_tready = (state == S_COLLECT) && aresetn;

  // ---- Flat buses (combinational from buffer) ----
  wire [KERNEL_SIZE*DATA_WIDTH-1:0] pixels_flat;
  wire [KERNEL_SIZE*DATA_WIDTH-1:0] weights_flat;

  genvar gi;
  generate
    for (gi = 0; gi < KERNEL_SIZE; gi = gi + 1) begin : pack
      assign pixels_flat [(gi+1)*DATA_WIDTH-1 -: DATA_WIDTH] = buf_r[gi];
      assign weights_flat[(gi+1)*DATA_WIDTH-1 -: DATA_WIDTH] = buf_r[gi+KERNEL_SIZE];
    end
  endgenerate

  // ---- Core signals ----
  reg  core_valid_in;
  wire core_ready_out;
  wire core_valid_out;
  wire [DATA_WIDTH-1:0] core_result;

  // ---- FSM ----
  always @(posedge aclk) begin
    if (!aresetn) begin
      state         <= S_COLLECT;
      byte_cnt      <= 0;
      core_valid_in <= 0;
    end else begin
      core_valid_in <= 0; // default

      case (state)
        S_COLLECT: begin
          if (s_axis_tvalid && s_axis_tready) begin
            buf_r[byte_cnt] <= s_axis_tdata;
            if (byte_cnt == TOTAL_BYTES - 1) begin
              byte_cnt <= 0;
              state    <= S_FIRE;
            end else begin
              byte_cnt <= byte_cnt + 1;
            end
          end
        end

        S_FIRE: begin
          // Wait for core to be ready then fire
          if (core_ready_out) begin
            core_valid_in <= 1;
            state         <= S_WAIT;
          end
        end

        S_WAIT: begin
          // Wait for result to come out then go back to collecting
          if (core_valid_out)
            state <= S_COLLECT;
        end

        default: state <= S_COLLECT;
      endcase
    end
  end

  // ---- CNN core ----
  cnn_layer #(
    .DATA_WIDTH (DATA_WIDTH),
    .ACC_WIDTH  (ACC_WIDTH),
    .KERNEL_SIZE(KERNEL_SIZE)
  ) u_core (
    .clk      (aclk),
    .rst_n    (aresetn),
    .valid_in (core_valid_in),
    .ready_out(core_ready_out),
    .pixels   (pixels_flat),
    .weights  (weights_flat),
    .result   (core_result),
    .valid_out(core_valid_out)
  );

  // ---- Output register ----
  // AXI-S rule: tvalid must stay high until tready is seen.
  // We latch the result and hold tvalid until the downstream
  // acknowledges on a rising edge (tready & tvalid both high).
  always @(posedge aclk) begin
    if (!aresetn) begin
      m_axis_tdata  <= 0;
      m_axis_tvalid <= 0;
      m_axis_tlast  <= 0;
    end else begin
      if (core_valid_out && !m_axis_tvalid) begin
        // Latch new result — only when output is free
        m_axis_tdata  <= core_result;
        m_axis_tvalid <= 1;
        m_axis_tlast  <= 1;
      end else if (m_axis_tvalid && m_axis_tready) begin
        // Downstream consumed it this cycle — clear next cycle
        m_axis_tvalid <= 0;
        m_axis_tlast  <= 0;
      end
    end
  end

endmodule
