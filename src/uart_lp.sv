module uart_lp (
    uart_if uif
);

  logic [DATALEN-1:0] rx_wdata, rx_rdata, tx_wdata, tx_rdata;
  logic rx_push, rx_pop, rx_full, rx_empty;
  logic tx_push, tx_pop, tx_full, tx_empty;

  uart_core u_uart_core (.uif(uif));
  fifo u_rff (
      .clk(uif.clk),
      .rst(uif.rst),
      .wr(rx_push),
      .rd(rx_pop),
      .wdata(rx_wdata),
      .rdata(rx_rdata),
      .full(rx_full),
      .mpty(rx_empty)
  );
  fifo u_tff (
      .clk(uif.clk),
      .rst(uif.rst),
      .wr(tx_push),
      .rd(tx_pop),
      .wdata(tx_wdata),
      .rdata(tx_rdata),
      .full(tx_full),
      .mpty(tx_empty)
  );

  assign rx_wdata = uif.rx_data;
  assign rx_push = uif.rx_done;
  assign rx_pop = ~tx_full;
  assign tx_wdata = rx_rdata;
  assign tx_push = ~rx_empty;
  assign tx_pop = uif.tx_busy;
  assign uif.tx_data = tx_rdata;
  assign uif.tx_start = ~tx_empty;
  assign uif.valid = tx_push;
  assign uif.fifo_rdata = rx_rdata;
endmodule
