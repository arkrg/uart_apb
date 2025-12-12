module uart_counter_top #(
) (
           uart_if       uif,
    input  logic         clk,
    input  logic         rst,
    input                rx,
    input  logic         btn_ud,
    input  logic         btn_clr,
    input  logic         btn_rnstp,
    output               tx,
    output logic   [7:0] fnd_data,
    output logic   [3:0] fnd_com

);

  assign tx = uif.tx;
  logic cmd_clr, cmd_rnstp, cmd_ud;
  logic ucmd_clr, ucmd_rnstp, ucmd_ud;
  logic clr_d, rnstp_d, ud_d;

  btn_debouncer u_btn_debouncer[2:0] (
      .clk,
      .rst,
      .d({btn_ud, btn_clr, btn_rnstp}),
      .edge_d({ud_d, clr_d, rnstp_d})
  );
  uartcmd u_ucmd (
      .uif(uif),
      .ucmd_ud,
      .ucmd_clr,
      .ucmd_rnstp
  );
  // encoder
  assign cmd_clr = ucmd_clr | clr_d;
  assign cmd_rnstp = ucmd_rnstp | rnstp_d;
  assign cmd_ud = ucmd_ud | ud_d;

  updn_counter_top u_counter (
      .clk,
      .rst,
      .ud(cmd_ud),
      .clr(cmd_clr),
      .rnstp(cmd_rnstp),
      .fnd_data,
      .fnd_com
  );
endmodule

module uartcmd (
    uart_if uif,
    output logic ucmd_ud,
    output logic ucmd_clr,
    output logic ucmd_rnstp
);
  logic [DATALEN-1:0] ucmd;
  uart_fifo u_uf (.uif(uif));

  always_ff @(posedge uif.clk or posedge uif.rst) begin
    if (uif.rst) begin
      ucmd <= 0;
    end else begin
      if (uif.valid) begin
        ucmd <= uif.fifo_rdata;
      end else ucmd <= 0;
    end
  end
  always_comb begin
    {ucmd_ud, ucmd_clr, ucmd_rnstp} = 3'b000;
    case (ucmd)
      "m": {ucmd_ud, ucmd_clr, ucmd_rnstp} = 3'b100;
      "c": {ucmd_ud, ucmd_clr, ucmd_rnstp} = 3'b010;
      "r": {ucmd_ud, ucmd_clr, ucmd_rnstp} = 3'b001;
    endcase
  end
endmodule


