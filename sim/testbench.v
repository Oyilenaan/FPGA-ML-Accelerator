`timescale 1ns/1ps
module testbench;
  reg clk;
  reg [7:0] pixel_in;
  wire [7:0] pixel_out;

  // Instantiate the CNN layer module
  cnn_layer dut (.clk(clk), .pixel_in(pixel_in), .pixel_out(pixel_out));

  // Clock generation (5ns period)
  initial begin
    clk = 0;
    forever #5 clk = ~clk;  // 10ns period (5ns high, 5ns low)
  end

  // Dump waveform data to a VCD file (for viewing with a waveform viewer)
  initial begin
    $dumpfile("sim/waveform.vcd");
    $dumpvars(1, testbench);  // Level 1 to include submodule signals (dut)
  end

  // Test stimulus
  initial begin
    // Test Case 1: Input = 0 (0 * 3 = 0)
    pixel_in = 8'h00;
    #20; // Wait for 20ns (2 clock cycles)
    $display("[Test 1] Input: %h → Output: %h", pixel_in, pixel_out);

    // Test Case 2: Input = 1 (1 * 3 = 3)
    pixel_in = 8'h01;
    #20;
    $display("[Test 2] Input: %h → Output: %h", pixel_in, pixel_out);

    // Test Case 3: Input = 8'hFF (255 * 3 = 765 → 8'hFD due to 8-bit overflow)
    pixel_in = 8'hFF;
    #20;
    $display("[Test 3] Input: %h → Output: %h", pixel_in, pixel_out);

    // Test Case 4: Input = 8'h55 (85 * 3 = 255 → 8'hFF)
    pixel_in = 8'h55;
    #20;
    $display("[Test 4] Input: %h → Output: %h", pixel_in, pixel_out);

    // Test Case 5: Input = 8'hAA (170 * 3 = 510 → 8'hFE)
    pixel_in = 8'hAA;
    #20;
    $display("[Test 5] Input: %h → Output: %h", pixel_in, pixel_out);

    $finish;
  end
endmodule