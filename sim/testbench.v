// =============================================================================
// testbench.v — Self-Checking Testbench for cnn_layer
// -----------------------------------------------------------------------------
// Workflow:
//   1. Run sim/scripts/golden_model.py first to generate:
//        sim/inputs.hex   (pixel windows + weights)
//        sim/expected.hex (expected outputs)
//   2. Simulate this testbench with Icarus Verilog or Vivado Sim.
//   3. Testbench reads both files, drives the DUT, and auto-checks every output.
//
// Pass/fail output:
//   PASS [idx 000]: expected=ff  got=ff
//   FAIL [idx 045]: expected=3a  got=00   ← caught a bug!
//   ...
//   =============================================
//   RESULT: 256/256 tests passed.
//   =============================================
// =============================================================================
`timescale 1ns/1ps

module testbench;

  // ---- Parameters (must match DUT) ----
  parameter DATA_WIDTH  = 8;
  parameter ACC_WIDTH   = 20;
  parameter KERNEL_SIZE = 9;
  parameter NUM_TESTS   = 256;
  parameter CLK_PERIOD  = 10; // ns

  // ---- DUT ports ----
  reg                              clk;
  reg                              rst_n;
  reg                              valid_in;
  wire                             ready_out;
  reg  [KERNEL_SIZE*DATA_WIDTH-1:0] pixels;
  reg  [KERNEL_SIZE*DATA_WIDTH-1:0] weights;
  wire [DATA_WIDTH-1:0]             result;
  wire                              valid_out;

  // ---- DUT instantiation ----
  cnn_layer #(
    .DATA_WIDTH (DATA_WIDTH),
    .ACC_WIDTH  (ACC_WIDTH),
    .KERNEL_SIZE(KERNEL_SIZE)
  ) dut (
    .clk      (clk),
    .rst_n    (rst_n),
    .valid_in (valid_in),
    .ready_out(ready_out),
    .pixels   (pixels),
    .weights  (weights),
    .result   (result),
    .valid_out(valid_out)
  );

  // ---- Clock ----
  initial clk = 0;
  always #(CLK_PERIOD/2) clk = ~clk;

  // ---- Waveform dump ----
  initial begin
    $dumpfile("sim/waveform.vcd");
    $dumpvars(0, testbench);
  end

  // ---- Test vector storage ----
  reg [DATA_WIDTH-1:0] pix_mem [0:NUM_TESTS*KERNEL_SIZE-1];
  reg [DATA_WIDTH-1:0] wgt_mem [0:NUM_TESTS*KERNEL_SIZE-1];
  reg [DATA_WIDTH-1:0] exp_mem [0:NUM_TESTS-1];

  // ---- Result tracking ----
  integer pass_count;
  integer fail_count;
  integer test_idx;     // which test vector we sent
  integer check_idx;    // which result we're checking

  // ---- Load hex files ----
  // inputs.hex format: 9 pixel bytes then 9 weight bytes per line
  // We flatten them into pix_mem and wgt_mem
  integer fd, r, k;
  reg [7:0] tmp;

  task load_inputs;
    integer line;
    begin
      fd = $fopen("sim/inputs.hex", "r");
      if (fd == 0) begin
        $display("ERROR: Could not open sim/inputs.hex");
        $display("       Run: python3 sim/scripts/golden_model.py first.");
        $finish;
      end
      for (line = 0; line < NUM_TESTS; line = line + 1) begin
        // Read 9 pixel bytes
        for (k = 0; k < KERNEL_SIZE; k = k + 1) begin
          r = $fscanf(fd, " %h", tmp);
          pix_mem[line*KERNEL_SIZE + k] = tmp;
        end
        // Read 9 weight bytes
        for (k = 0; k < KERNEL_SIZE; k = k + 1) begin
          r = $fscanf(fd, " %h", tmp);
          wgt_mem[line*KERNEL_SIZE + k] = tmp;
        end
      end
      $fclose(fd);
    end
  endtask

  task load_expected;
    integer line;
    begin
      fd = $fopen("sim/expected.hex", "r");
      if (fd == 0) begin
        $display("ERROR: Could not open sim/expected.hex");
        $finish;
      end
      for (line = 0; line < NUM_TESTS; line = line + 1) begin
        r = $fscanf(fd, " %h", exp_mem[line]);
      end
      $fclose(fd);
    end
  endtask

  // ---- Drive task: pack arrays into flat bus ----
  task drive_input;
    input integer idx;
    integer j;
    begin
      for (j = 0; j < KERNEL_SIZE; j = j + 1) begin
        pixels [(j+1)*DATA_WIDTH-1 -: DATA_WIDTH] = pix_mem[idx*KERNEL_SIZE + j];
        weights[(j+1)*DATA_WIDTH-1 -: DATA_WIDTH] = wgt_mem[idx*KERNEL_SIZE + j];
      end
    end
  endtask

  // ---- Check result on valid_out ----
  always @(posedge clk) begin
    if (valid_out) begin
      if (result === exp_mem[check_idx]) begin
        $display("  PASS [idx %03d]: expected=%02h  got=%02h",
                 check_idx, exp_mem[check_idx], result);
        pass_count = pass_count + 1;
      end else begin
        $display("  FAIL [idx %03d]: expected=%02h  got=%02h  *** MISMATCH ***",
                 check_idx, exp_mem[check_idx], result);
        fail_count = fail_count + 1;
      end
      check_idx = check_idx + 1;
    end
  end

  // ---- Main stimulus ----
  initial begin
    // Initialise
    rst_n      = 0;
    valid_in   = 0;
    pixels     = 0;
    weights    = 0;
    pass_count = 0;
    fail_count = 0;
    test_idx   = 0;
    check_idx  = 0;

    // Load vectors from golden model
    load_inputs;
    load_expected;
    $display("Loaded %0d test vectors from golden model.", NUM_TESTS);

    // Reset for 3 cycles
    repeat(3) @(posedge clk);
    rst_n = 1;
    @(posedge clk);

    // Drive all test vectors
    while (test_idx < NUM_TESTS) begin
      @(posedge clk);
      if (ready_out) begin
        drive_input(test_idx);
        valid_in = 1;
        @(posedge clk);
        valid_in = 0;
        test_idx = test_idx + 1;
      end
    end

    // Wait for all results to come back (pipeline drain)
    // Latency = 9 (serialize) + 3 (MAC pipeline) + 1 (ReLU) = 13 cycles + margin
    repeat(30) @(posedge clk);

    // Final report
    $display("");
    $display("=============================================");
    if (fail_count == 0)
      $display("RESULT: %0d/%0d tests PASSED.", pass_count, NUM_TESTS);
    else
      $display("RESULT: %0d FAILED, %0d passed.", fail_count, pass_count);
    $display("=============================================");

    $finish;
  end

endmodule
