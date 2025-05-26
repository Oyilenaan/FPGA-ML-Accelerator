module cnn_layer (
  input clk,
  input [7:0] pixel_in,
  output reg [7:0] pixel_out
);
  always @(posedge clk) begin
    pixel_out <= pixel_in * 3; // Multiply input by kernel value 3
  end
endmodule
