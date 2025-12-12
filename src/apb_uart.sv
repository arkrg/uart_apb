module apb_uart_periph (
    // apb insterface
    apb_if.completer apb_c,
    // external signal
    input logic rx,
    output logic tx
);
  logic                  pclk;
  logic                  presetn;
  logic                  penable;
  logic                  pready;
  logic [           4:0] paddr;
  logic                  pwrite;
  logic [DATA_WIDTH-1:0] pwdata;
  logic [DATA_WIDTH-1:0] prdata;
  // apb assign
  assign pclk = apb_c.PCLK;
  assign presetn = apb_c.PRESETn;
  assign penable = apb_c.PENABLE;
  assign psel = apb_c.PSEL;
  assign apb_c.PREADY = pready;
  assign paddr = apb_c.PADDR[4:0];
  assign pwrite = apb_c.PWRITE;
  assign pwdata = apb_c.PWDATA;
  assign apb_c.PRDATA = prdata;
  // uarrt assign
  wire PENABLE_AND_PSEL = penable & psel;
  uart u_uart (
      .clk(pclk),
      .rst(~presetn),
      .tx,
      .rx,
      .addr(paddr),
      .we(pwrite),
      .rd(PENABLE_AND_PSEL & ~pready),
      .en(PENABLE_AND_PSEL),
      .wdata(pwdata),
      .rdata(prdata)
  );
  always_ff @(posedge pclk or negedge presetn) begin
    if (!presetn) pready <= 1'b0;
    else begin
      if (PENABLE_AND_PSEL) pready <= 1'b1;  // access phase
      else pready <= 1'b0;
    end
  end
endmodule

