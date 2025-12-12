module fnd_controller #(
    parameter DIV_1KHZ = 100_000,
    parameter MAX_COUNT = 9_999,
    parameter WIDTH_COUNTER = $clog2(MAX_COUNT)
) (
    input clk,
    input rst,
    input [WIDTH_COUNTER-1:0] count,
    output [7:0] fnd_data,
    output [3:0] fnd_com

);
  // 1khz
  // 100_000_000 : 1
  // 100_000 : 1K
  wire tick_1khz;
  wire [1:0] mod2_count;
  wire [3:0] digit_1, digit_10, digit_100, digit_1000;
  reg [3:0] _fnd_com;
  reg [3:0] _fnd_data;

  tick_generator #(
      .DIV(DIV_1KHZ)
  ) u_1khz_tick_generator (
      .clk (clk),
      .rst (rst),
      .tick(tick_1khz)
  );

  mod2_counter u_scan_counter (
      .clk(tick_1khz),
      .rst(rst),
      .mod2_count(mod2_count)
  );
  always @(*) begin
    case (mod2_count)
      2'b00:   _fnd_com = 4'b1110;
      2'b01:   _fnd_com = 4'b1101;
      2'b10:   _fnd_com = 4'b1011;
      2'b11:   _fnd_com = 4'b0111;
      default: _fnd_com = 4'b1111;
    endcase
  end
  assign fnd_com = _fnd_com;
  //--------------------------------------------------

  digit_spliter #(
      .MAX_COUNT(MAX_COUNT)
  ) u_digit_spliter (
      .in(count),
      .digit_1000(digit_1000),
      .digit_100(digit_100),
      .digit_10(digit_10),
      .digit_1(digit_1)
  );

  always @(*) begin
    case (mod2_count)
      2'b00:   _fnd_data = digit_1;
      2'b01:   _fnd_data = digit_10;
      2'b10:   _fnd_data = digit_100;
      2'b11:   _fnd_data = digit_1000;
      default: _fnd_data = digit_1;
    endcase
  end

  bcd_decoder u_bcd_decoder (
      .bcd(_fnd_data),
      .fnd_data(fnd_data)
  );

endmodule

module mod2_counter (
    input clk,
    input rst,
    output [1:0] mod2_count
);
  reg [1:0] r_count;

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      r_count <= 0;
    end else begin
      r_count <= r_count + 1;
    end
  end

  assign mod2_count = r_count;

endmodule

module digit_spliter #(
    parameter MAX_COUNT = 9_999,
    parameter WIDTH_COUNTER = $clog2(MAX_COUNT)
) (
    input [WIDTH_COUNTER-1:0] in,
    output [3:0] digit_1000,
    output [3:0] digit_100,
    output [3:0] digit_10,
    output [3:0] digit_1
);

  assign digit_1 = in % 10;
  assign digit_10 = in / 10 % 10;
  assign digit_100 = in / 100 % 10;
  assign digit_1000 = in / 1000 % 10;

endmodule

module bcd_decoder (
    input  [3:0] bcd,
    output [7:0] fnd_data
);

  reg [7:0] _fnd_data;

  always @(*) begin
    case (bcd)
      4'b0000: _fnd_data = 8'hc0;
      4'b0001: _fnd_data = 8'hf9;
      4'b0010: _fnd_data = 8'ha4;
      4'b0011: _fnd_data = 8'hb0;

      4'b0100: _fnd_data = 8'h99;
      4'b0101: _fnd_data = 8'h92;
      4'b0110: _fnd_data = 8'h99;
      4'b0111: _fnd_data = 8'h92;

      4'b1000: _fnd_data = 8'h80;
      4'b1001: _fnd_data = 8'h90;
      4'b1010: _fnd_data = 8'h88;
      4'b1011: _fnd_data = 8'h83;

      4'b1100: _fnd_data = 8'hc6;
      4'b1101: _fnd_data = 8'ha1;
      4'b1110: _fnd_data = 8'h7f;
      4'b1111: _fnd_data = 8'hff;
      default: _fnd_data = 8'hff;
    endcase
  end

  assign fnd_data = _fnd_data;
endmodule
