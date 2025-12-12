module fifo #(
    parameter int WIDTH_DATA = 8,
    parameter int DEPTH_DATA = 16
) (
    input  logic                  clk,
    input  logic                  rst,
    input  logic                  wr,
    input  logic                  rd,
    input  logic [WIDTH_DATA-1:0] wdata,
    output logic [WIDTH_DATA-1:0] rdata,
    output logic                  full,
    output logic                  mpty
);
  localparam int WIDTH_ADDR = $clog2(DEPTH_DATA);
  logic [WIDTH_ADDR-1:0] waddr, raddr;
  logic w_en;

  fifo_mem #(
      .WIDTH_DATA(WIDTH_DATA),
      .DEPTH_DATA(DEPTH_DATA)
  ) u_ram (
      .*,
      .w_en
  );
  fifo_controller #(
      .WIDTH_DATA(WIDTH_DATA),
      .DEPTH_DATA(DEPTH_DATA)
  ) u_ctrl (
      .*
  );
  assign w_en = wr & (~full);

endmodule

module fifo_mem #(
    parameter int WIDTH_DATA = 8,
    parameter int DEPTH_DATA = 4,
    parameter int WDITH_ADDR = $clog2(DEPTH_DATA)
) (
    input logic clk,
    input logic w_en,
    input logic [WDITH_ADDR-1:0] waddr,
    input logic [WDITH_ADDR-1:0] raddr,
    input logic [WIDTH_DATA-1:0] wdata,
    output logic [WIDTH_DATA-1:0] rdata
);
  logic [WIDTH_DATA-1:0] mem[DEPTH_DATA];
  always_ff @(posedge clk) begin
    if (w_en) begin
      mem[waddr] <= wdata;
    end
  end
  assign rdata = mem[raddr];
  genvar i;
  generate
    for (i = 0; i < DEPTH_DATA; i++) begin : gen_mem_
      logic [WIDTH_DATA-1:0] mem_;
      assign mem_ = mem[i];
    end
  endgenerate

endmodule

// module fifo_controller #(
//     parameter int WIDTH_DATA = 8,
//     parameter int DEPTH_DATA = 4,
//     parameter int WDITH_ADDR = $clog2(DEPTH_DATA)
// ) (
//     input  logic                  clk,
//     input  logic                  rst,
//     input  logic                  wr,
//     input  logic                  rd,
//     output logic [WDITH_ADDR-1:0] waddr,
//     output logic [WDITH_ADDR-1:0] raddr,
//     output logic                  full,
//     output logic                  mpty
// );
//
//   logic [WDITH_ADDR-1:0] c_waddr, n_waddr;
//   logic [WDITH_ADDR-1:0] c_raddr, n_raddr;
//   logic c_full, n_full;
//   logic c_mpty, n_mpty;
//
//   assign full  = c_full;
//   assign mpty  = c_mpty;
//   assign raddr = c_raddr;
//   assign waddr = c_waddr;
//
//   always_ff @(posedge clk or posedge rst) begin
//     if (rst) begin
//       c_waddr <= 0;
//       c_raddr <= 0;
//       c_full  <= 0;
//       c_mpty  <= 1;
//     end else begin
//       c_waddr <= n_waddr;
//       c_raddr <= n_raddr;
//       c_full  <= n_full;
//       c_mpty  <= n_mpty;
//     end
//   end
//
//   always_comb begin
//     n_waddr = c_waddr;
//     n_raddr = c_raddr;
//     n_full  = c_full;
//     n_mpty  = c_mpty;
//     case ({
//       wr, rd
//     })
//       2'b01: begin  // pop
//         if (c_mpty == 0) begin
//           n_raddr = c_raddr + 1;
//           n_full  = 0;
//           if (c_waddr == n_raddr) n_mpty = 1;
//         end
//       end
//       2'b10: begin
//         if (c_full == 0) begin
//           n_waddr = c_waddr + 1;
//           n_mpty  = 0;
//           if (n_waddr == c_raddr) begin
//             n_full = 1;
//           end
//         end
//       end
//       2'b11: begin
//         if (c_full) begin  // pop만
//           n_raddr = c_raddr + 1;
//           n_full  = 0;
//         end else if (c_mpty) begin
//           n_waddr = c_waddr + 1;
//           n_mpty  = 0;
//         end else begin
//           n_raddr = c_raddr + 1;
//           n_waddr = c_waddr + 1;
//         end
//       end
//     endcase
//   end
// endmodule


module fifo_controller #(
    parameter int WIDTH_DATA = 8,
    parameter int DEPTH_DATA = 4,
    parameter int WDITH_ADDR = $clog2(DEPTH_DATA)
) (
    input logic clk,
    input logic rst,
    input logic wr,
    input logic rd,
    output logic [WDITH_ADDR-1:0] waddr,
    output logic [WDITH_ADDR-1:0] raddr,
    output logic mpty,
    output logic full
);
  logic c_swptr, n_swptr;
  logic c_srptr, n_srptr;
  logic [WDITH_ADDR-1:0] c_rptr, n_rptr;
  logic [WDITH_ADDR-1:0] c_wptr, n_wptr;

  assign waddr = c_wptr;
  assign raddr = c_rptr;

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      c_wptr  <= 0;
      c_swptr <= 0;
      c_rptr  <= 0;
      c_srptr <= 0;
    end else begin
      c_wptr  <= n_wptr;
      c_swptr <= n_swptr;
      c_rptr  <= n_rptr;
      c_srptr <= n_srptr;
    end

  end

  always_comb begin
    n_wptr  = c_wptr;
    n_swptr = c_swptr;
    if (wr) begin
      if (~full) begin
        if (c_wptr == DEPTH_DATA - 1) begin
          n_wptr  = 0;
          n_swptr = ~c_swptr;
        end else begin
          n_wptr = c_wptr + 1;
        end
      end
    end
  end

  always_comb begin
    n_rptr  = c_rptr;
    n_srptr = c_srptr;
    if (rd) begin
      if (~mpty) begin
        if (c_rptr == DEPTH_DATA - 1) begin
          n_rptr  = 0;
          n_srptr = ~c_srptr;
        end else begin
          n_rptr = c_rptr + 1;
        end
      end
    end
  end

  assign full = (c_wptr == c_rptr) && (c_swptr != c_srptr);
  assign mpty = (c_wptr == c_rptr) && (c_swptr == c_srptr);
endmodule
