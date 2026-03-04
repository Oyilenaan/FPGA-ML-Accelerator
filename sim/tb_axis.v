`timescale 1ns/1ps
module tb_axis;

  parameter DATA_WIDTH  = 8;
  parameter KERNEL_SIZE = 9;
  parameter TOTAL_BYTES = 18;
  parameter NUM_TESTS   = 256;
  parameter CLK_PERIOD  = 10;

  reg        aclk, aresetn;
  reg  [7:0] s_axis_tdata;
  reg        s_axis_tvalid, s_axis_tlast;
  wire       s_axis_tready;
  wire [7:0] m_axis_tdata;
  wire       m_axis_tvalid, m_axis_tlast;
  reg        m_axis_tready;

  cnn_layer_axis #(.DATA_WIDTH(8),.KERNEL_SIZE(9)) dut (
    .aclk(aclk),.aresetn(aresetn),
    .s_axis_tdata(s_axis_tdata),.s_axis_tvalid(s_axis_tvalid),
    .s_axis_tlast(s_axis_tlast),.s_axis_tready(s_axis_tready),
    .m_axis_tdata(m_axis_tdata),.m_axis_tvalid(m_axis_tvalid),
    .m_axis_tlast(m_axis_tlast),.m_axis_tready(m_axis_tready)
  );

  initial aclk = 0;
  always #(CLK_PERIOD/2) aclk = ~aclk;

  initial begin
    $dumpfile("sim/waveform_axis.vcd");
    $dumpvars(0, tb_axis);
  end

  // ---- Test vector storage ----
  reg [7:0] pix_mem [0:NUM_TESTS*KERNEL_SIZE-1];
  reg [7:0] wgt_mem [0:NUM_TESTS*KERNEL_SIZE-1];
  reg [7:0] exp_mem [0:NUM_TESTS-1];

  integer fd, r, k;
  reg [7:0] tmp;

  task load_vectors;
    integer line;
    begin
      fd = $fopen("sim/inputs.hex", "r");
      if (fd == 0) begin $display("ERROR: sim/inputs.hex not found"); $finish; end
      for (line = 0; line < NUM_TESTS; line = line + 1) begin
        for (k = 0; k < KERNEL_SIZE; k = k + 1) begin
          r = $fscanf(fd, " %h", tmp); pix_mem[line*KERNEL_SIZE+k] = tmp;
        end
        for (k = 0; k < KERNEL_SIZE; k = k + 1) begin
          r = $fscanf(fd, " %h", tmp); wgt_mem[line*KERNEL_SIZE+k] = tmp;
        end
      end
      $fclose(fd);
      fd = $fopen("sim/expected.hex", "r");
      if (fd == 0) begin $display("ERROR: sim/expected.hex not found"); $finish; end
      for (line = 0; line < NUM_TESTS; line = line + 1)
        r = $fscanf(fd, " %h", exp_mem[line]);
      $fclose(fd);
    end
  endtask

  // ---- Send one byte, blocking on tready ----
  task send_byte;
    input [7:0] data;
    input       last;
    begin
      @(negedge aclk);           // drive on falling edge, sample on rising
      s_axis_tdata  = data;
      s_axis_tvalid = 1;
      s_axis_tlast  = last;
      @(posedge aclk);
      while (!s_axis_tready) @(posedge aclk);
      @(negedge aclk);
      s_axis_tvalid = 0;
      s_axis_tlast  = 0;
    end
  endtask

  task send_packet;
    input integer idx;
    integer b;
    begin
      for (b = 0; b < KERNEL_SIZE; b = b + 1)
        send_byte(pix_mem[idx*KERNEL_SIZE+b], 0);
      for (b = 0; b < KERNEL_SIZE; b = b + 1)
        send_byte(wgt_mem[idx*KERNEL_SIZE+b], b == KERNEL_SIZE-1);
    end
  endtask

  // ---- Blocking receive: wait for tvalid then capture ----
  reg [7:0] rx_data;
  task recv_result;
    begin
      // Hold tready low so we control when we consume
      m_axis_tready = 0;
      // Wait for tvalid
      @(posedge aclk);
      while (!m_axis_tvalid) @(posedge aclk);
      // Now capture the data
      rx_data = m_axis_tdata;
      // Acknowledge
      m_axis_tready = 1;
      @(posedge aclk);
      m_axis_tready = 0;
    end
  endtask

  integer i, pass_count, fail_count;

  initial begin
    aresetn=0; s_axis_tvalid=0; s_axis_tlast=0;
    s_axis_tdata=0; m_axis_tready=0;
    pass_count=0; fail_count=0;

    load_vectors;
    $display("Loaded %0d test vectors.", NUM_TESTS);

    repeat(3) @(posedge aclk);
    aresetn=1;
    @(posedge aclk);

    $display("--- AXI-Stream: 256 packets ---");

    for (i = 0; i < NUM_TESTS; i = i + 1) begin
      fork
        send_packet(i);
        recv_result;
      join

      if (rx_data === exp_mem[i]) begin
        $display("  PASS [idx %03d]: expected=%02h  got=%02h", i, exp_mem[i], rx_data);
        pass_count = pass_count + 1;
      end else begin
        $display("  FAIL [idx %03d]: expected=%02h  got=%02h  *** MISMATCH ***", i, exp_mem[i], rx_data);
        fail_count = fail_count + 1;
      end
    end

    $display("");
    $display("=============================================");
    if (fail_count == 0)
      $display("RESULT: %0d/%0d AXI-Stream tests PASSED.", pass_count, NUM_TESTS);
    else
      $display("RESULT: %0d FAILED, %0d passed.", fail_count, pass_count);
    $display("=============================================");
    $finish;
  end

endmodule
