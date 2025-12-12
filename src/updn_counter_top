import cnt_pkg::*;
module updn_counter_top #(
) (
    input  logic       clk,
    input  logic       rst,
    input  logic       ud,
    input  logic       clr,
    input  logic       rnstp,
    output logic [7:0] fnd_data,
    output logic [3:0] fnd_com
);
  localparam int WIDTHCOUNTER = $clog2(MAX_COUNT);
  logic [WIDTHCOUNTER-1:0] count;
  updn_counter_core u_counter_core (
      .clk,
      .rst,
      .ud,
      .clr,
      .rnstp,
      .count
  );

  fnd_controller u_fndcontroller (
      .clk(clk),
      .rst(rst),
      .count(count),
      .fnd_com(fnd_com),
      .fnd_data(fnd_data)
  );

endmodule
module updn_counter_core #(
    parameter WIDTH_COUNTER = $clog2(MAX_COUNT)
) (
    input  logic                     clk,
    input  logic                     rst,
    input  logic                     ud,
    input  logic                     clr,
    input  logic                     rnstp,
    output logic [WIDTH_COUNTER-1:0] count

);
  logic ctrl_ud, ctrl_en, ctrl_clr;
  updn_counter_controller u_controller (
      .clk,
      .rst,
      .ud,
      .rnstp,
      .clr,
      .ctrl_ud,
      .ctrl_clr,
      .ctrl_en
  );

  updn_counter_datapath u_datapath (
      .clk,
      .rst,
      .ud (ctrl_ud),
      .clr(ctrl_clr),
      .en (ctrl_en),
      .count
  );

endmodule

module updn_counter_datapath #(
    parameter int WIDTH_COUNTER = $clog2(MAX_COUNT)
) (
    input                      clk,
    input                      rst,
    input                      ud,
    input                      clr,
    input                      en,
    output [WIDTH_COUNTER-1:0] count
);
  reg [3:0] _fnd_com;
  wire tick;

  tick_generator_wctrl u_tick_generator (
      .clk (clk),
      .rst (rst),
      .en  (en),
      .clr (clr),
      .tick(tick)
  );

  updn_counter u_counter (
      .rst(rst),
      .clk(clk),
      .tick(tick),
      .ud(ud),
      .clr(clr),
      .count(count)
  );

endmodule

module updn_counter #(
    parameter WIDTH = $clog2(MAX_COUNT)
) (
    input              rst,
    input              clk,
    input              tick,
    input              ud,
    input              clr,
    output [WIDTH-1:0] count
);
  reg [WIDTH-1:0] r_count;

  always @(posedge clk or posedge rst or posedge clr) begin
    if (rst | clr) begin
      r_count <= 0;
    end else begin
      if (tick) begin
        if (ud == 1) begin  // up
          if (r_count < MAX_COUNT - 1) begin
            r_count <= r_count + 1;
          end else r_count <= 0;
        end else begin  // dn 
          if (r_count > 0) begin
            r_count <= r_count - 1;
          end else r_count <= MAX_COUNT - 1;

        end
      end
    end
  end
  assign count = r_count;
endmodule

module tick_generator_wctrl #(
) (
    input  rst,
    input  clk,
    input  clr,
    input  en,
    output tick
);
  reg [WIDTH_COUNTER-1:0] r_count;

  always @(posedge clk or posedge rst or posedge clr) begin
    if (rst | clr) begin
      r_count <= 0;
    end else begin
      if (en) begin
        if (r_count > DIV - 1) r_count <= 0;
        else r_count <= r_count + 1;
      end
    end
  end

  assign tick = (r_count == DIV - 1);
endmodule

module updn_counter_controller (
    input logic clk,
    input logic rst,
    input logic rnstp,
    input logic clr,
    input logic ud,

    output logic ctrl_en,
    output logic ctrl_ud,
    output logic ctrl_clr
);
  parameter DN_0 = 0, UP_1 = 1;
  parameter DE_0 = 0, EN_1 = 1;
  logic c_en, c_ud, c_clr;
  logic n_en, n_ud, n_clr;

  assign ctrl_en  = c_en;
  assign ctrl_ud  = c_ud;
  assign ctrl_clr = c_clr;

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      c_en <= EN_1;
      c_ud <= UP_1;
    end else begin
      if (rnstp) c_en <= ~c_en;
      if (ud) c_ud <= ~c_ud;
      if (clr) c_clr <= 1;
      else c_clr <= 0;
    end
  end
endmodule

module btn_debouncer (
    input  clk,
    input  rst,
    input  d,
    output edge_d
);

  reg [3:0] q;
  reg d_q;
  wire and_q;
  always @(posedge clk or posedge rst) begin
    if (rst) q <= 0;
    else q <= {q[2:0], d};
  end

  assign and_q = &q;

  always @(posedge clk or posedge rst) begin
    if (rst) d_q <= 0;
    else d_q <= and_q;
  end
  assign edge_d = d_q & and_q;

endmodule

module tick_generator #(
    // 100M -> 10Hz
    parameter DIV = 10_000_000,
    parameter WIDTH_COUNTER = $clog2(DIV)
) (
    input  clk,
    input  rst,
    output tick
);
  reg [WIDTH_COUNTER-1:0] r_count;
  always @(posedge clk or posedge rst) begin
    if (rst) begin
      r_count <= 0;
    end else begin
      if (r_count > DIV - 1) r_count <= 0;
      else r_count <= r_count + 1;
    end
  end

  assign tick = (r_count == DIV - 1);
endmodule

