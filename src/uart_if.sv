import uart_pkg::*;
interface uart_if (
    input logic clk,
    input logic rst
);
  logic btick;
  logic [DATALEN-1:0] tx_data;
  logic tx_start;
  logic rx;
  logic tx;
  logic tx_busy;
  logic [DATALEN-1:0] rx_data;
  logic rx_busy;
  logic rx_done;
  logic [15:0] divisor;

  modport bdgen(input clk, input rst, input divisor, output btick);
  modport utx(
      input clk,
      input rst,
      input btick,
      input tx_data,
      input tx_start,
      output tx,
      output tx_busy
  );
  modport urx(
      input clk,
      input rst,
      input btick,
      input rx,
      output rx_data,
      output rx_busy,
      output rx_done
  );
endinterface
