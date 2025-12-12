import uart_pkg::*;
module uart (
    input               clk,
    input               rst,
    input               rx,
    output              tx,
    // internal signal
    input  logic [ 4:0] addr,
    input  logic        en,
    input  logic        we,
    input  logic        rd,
    input  logic [31:0] wdata,
    output logic [31:0] rdata
);
  logic [DATALEN-1:0] utx_data;
  logic [DATALEN-1:0] urx_data;
  logic               tx_full;
  logic               rx_empty;
  logic [       15:0] divisor;
  logic               urx_pop;
  uart_regFile u_uart_rf (
      .clk,
      .rst,
      .addr,
      .en,
      .we,
      .rd,
      .wdata,
      .rdata,
      .urx_empty(rx_empty),
      .urx_data,
      .urx_pop,
      .utx_full (tx_full),
      .utx_data,
      .utx_push,
      .divisor
  );
  uart_core u_uart_core (
      .clk,
      .rst,
      .tx,
      .rx,
      .rx_pop  (urx_pop),
      .tx_push (utx_push),
      .tx_wdata(utx_data),
      .rx_rdata(urx_data),
      .tx_full,
      .rx_empty,
      .divisor
  );
endmodule
module uart_regFile (
    input  logic               clk,
    input  logic               rst,
    // cpu
    input  logic [        4:0] addr,
    input  logic               we,
    input  logic               rd,
    input  logic               en,
    input  logic [       31:0] wdata,
    output logic [       31:0] rdata,
    // uart fifo
    input  logic               urx_empty,
    input  logic [DATALEN-1:0] urx_data,
    output logic               urx_pop,

    input  logic               utx_full,
    output logic [DATALEN-1:0] utx_data,
    output logic               utx_push,
    // control
    output logic [       15:0] divisor
);
  logic [31:0] RBR, THR, IER, IIR, FCR, LCR, MCR, LSR, MSR, SCR, DLL, DLH;
  assign divisor = {DLH[7:0], DLL[7:0]};
  logic [2:0] case_sel;
  logic RXFIFOE, TEMT, THRE, BIS, FE, PE, OE, DR;
  logic DLAB;
  assign case_sel = addr[4:2];
  assign DLAB = LCR[7];
  assign LSR = {RXFIFOE, TEMT, THRE, BIS, FE, PE, OE, DR};
  assign utx_data = THR;


  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      RBR <= 0;
      THR <= 0;
      IER <= 0;
      IIR <= 1;
      FCR <= 0;
      LCR <= 0;
      MCR <= 0;
      MSR <= 0;
      SCR <= 0;
      DLL <= 0;
      DLH <= 0;
      utx_push <= 0;
    end else begin
      utx_push <= 0;
      if (en) begin
        if (we) begin
          case (case_sel)
            3'b000: begin
              if (DLAB == 0) begin
                THR <= wdata;
                utx_push <= 1;  // 1 && ~tx_full? 
              end else DLL <= wdata;
            end
            3'b001: begin
              if (DLAB == 0) IER <= wdata;
              else DLH <= wdata;
            end
            3'b010: FCR <= wdata;
            3'b011: LCR <= wdata;
            3'b100: MCR <= wdata;
            3'b110: MSR <= wdata;
            3'b111: SCR <= wdata;
          endcase
        end
      end
    end
  end
  //with uart
  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      {RXFIFOE, BIS, FE, PE, OE, DR} <= 0;
      {TEMT, THRE} <= 0;
    end else begin
      if (urx_pop) RBR <= {24'd0, urx_data};
      DR   <= ~urx_empty;
      THRE <= ~utx_full;
    end
  end

  always_comb begin
    urx_pop = 0;
    rdata   = 'dz;
    case (case_sel)
      3'b000: begin
        if (DLAB == 0) begin
          rdata = RBR;
          if (~we & rd) urx_pop = 1;
        end else rdata = DLL;
      end
      3'b001: begin
        if (DLAB == 0) rdata = IER;
        else rdata = DLH;
      end
      3'b010: rdata = IIR;
      3'b011: rdata = LCR;
      3'b100: rdata = MCR;
      3'b101: rdata = LSR;
      3'b110: rdata = MSR;
      3'b111: rdata = SCR;
    endcase
  end

endmodule
module uart_core (
    input  logic               clk,
    input  logic               rst,
    input  logic               rx,
    output logic               tx,
    input  logic               rx_pop,
    input  logic               tx_push,
    input  logic [DATALEN-1:0] tx_wdata,
    output logic [DATALEN-1:0] rx_rdata,
    output logic               tx_full,
    output logic               rx_empty,
    input  logic [       15:0] divisor
);
  logic [DATALEN-1:0] tx_rdata, rx_wdata;
  uart_if uif (
      .clk,
      .rst
  );
  assign tx = uif.tx;
  assign uif.rx = rx;
  assign uif.divisor = divisor;
  uart_bdgen u_bdgen (.uif_b(uif.bdgen));
  uart_tx u_tx (.uif_t(uif.utx));
  uart_rx u_rx (.uif_r(uif.urx));

  fifo u_rff (
      .clk,
      .rst,
      .wr(rx_push),
      .rd(rx_pop),
      .wdata(rx_wdata),
      .rdata(rx_rdata),
      .full(rx_full),
      .mpty(rx_empty)
  );
  fifo u_tff (
      .clk,
      .rst,
      .wr(tx_push),
      .rd(tx_pop),
      .wdata(tx_wdata),
      .rdata(tx_rdata),
      .full(tx_full),
      .mpty(tx_empty)
  );

  assign rx_wdata = uif.rx_data;
  assign rx_push = uif.rx_done;
  assign tx_pop = ~uif.tx_busy;
  assign uif.tx_data = tx_rdata;
  assign uif.tx_start = ~tx_empty;

endmodule

module uart_tx (
    uart_if.utx uif_t
);
  localparam int WIDTHTICKCNT = $clog2(OSR);
  localparam int WIDTHBITCNT = $clog2(DATALEN);
  states_e c_state, n_state;
  reg [WIDTHBITCNT-1:0] c_bitcnt, n_bitcnt;
  reg [WIDTHTICKCNT-1:0] c_tickcnt, n_tickcnt;
  reg [DATALEN-1:0] c_txsr, n_txsr;
  reg n_tx, c_tx;
  reg n_busy, c_busy;

  assign uif_t.tx = c_tx;
  assign uif_t.tx_busy = c_busy;
  always @(posedge uif_t.clk or posedge uif_t.rst) begin
    if (uif_t.rst) begin
      c_state   <= IDLE;
      c_tx      <= 1;
      c_bitcnt  <= 0;
      c_tickcnt <= 0;
      c_busy    <= 0;
      c_txsr    <= 0;
    end else begin
      c_state   <= n_state;
      c_tx      <= n_tx;
      c_bitcnt  <= n_bitcnt;
      c_tickcnt <= n_tickcnt;
      c_busy    <= n_busy;
      c_txsr    <= n_txsr;
    end
  end

  always_comb begin
    n_state   = c_state;
    n_tx      = c_tx;
    n_bitcnt  = c_bitcnt;
    n_tickcnt = c_tickcnt;
    n_txsr    = c_txsr;
    n_busy    = c_busy;
    case (c_state)
      IDLE: begin
        n_tx = 1;
        if (uif_t.tx_start) begin
          n_state = START;
          n_txsr  = uif_t.tx_data;
        end
      end
      START: begin
        n_tx   = 0;
        n_busy = 1;
        if (uif_t.btick) begin
          if (c_tickcnt == OSR - 1) begin
            n_state   = DATA;
            n_tickcnt = 0;
          end else begin
            n_tickcnt = c_tickcnt + 1;
          end
        end
      end
      DATA: begin
        n_tx = c_txsr[0];
        if (uif_t.btick) begin
          if (c_tickcnt == OSR - 1) begin
            n_tickcnt = 0;
            if (c_bitcnt == DATALEN - 1) begin
              n_bitcnt = 0;
              n_state  = STOP;
            end else begin
              n_bitcnt = c_bitcnt + 1;
              n_txsr   = c_txsr >> 1;
            end
          end else begin
            n_tickcnt = c_tickcnt + 1;
          end
        end
      end
      STOP: begin
        n_tx = 1;
        if (uif_t.btick) begin
          if (c_tickcnt == OSR - 1) begin
            n_tickcnt = 0;
            n_state = IDLE;
            n_busy = 0;
          end else begin
            n_tickcnt = c_tickcnt + 1;
          end
        end
      end
    endcase
  end
endmodule

module uart_rx #(
) (
    uart_if.urx uif_r
);
  localparam int WIDTHTICKCNT = $clog2(OSR);
  localparam int WIDTHBITCNT = $clog2(DATALEN);
  states_e c_state, n_state;
  reg [DATALEN-1:0] c_data, n_data;
  reg c_done, n_done;
  reg c_busy, n_busy;
  reg [WIDTHTICKCNT-1:0] c_tickcnt, n_tickcnt;
  reg [WIDTHBITCNT-1:0] c_bitcnt, n_bitcnt;

  assign uif_r.rx_data = c_data;
  assign uif_r.rx_done = c_done;
  assign uif_r.rx_busy = c_busy;

  always_ff @(posedge uif_r.clk or posedge uif_r.rst) begin
    if (uif_r.rst) begin
      c_state   <= IDLE;
      c_done    <= 0;
      c_busy    <= 0;
      c_data    <= 0;
      c_tickcnt <= 0;
      c_bitcnt  <= 0;
    end else begin
      c_state   <= n_state;
      c_done    <= n_done;
      c_busy    <= n_busy;
      c_data    <= n_data;
      c_tickcnt <= n_tickcnt;
      c_bitcnt  <= n_bitcnt;
    end
  end

  always_comb begin
    n_state   = c_state;
    n_done    = c_done;
    n_busy    = c_busy;
    n_data    = c_data;
    n_tickcnt = c_tickcnt;
    n_bitcnt  = c_bitcnt;
    case (c_state)
      IDLE: begin
        n_state = (uif_r.rx == 0) ? START : IDLE;
        n_done  = 0;
        n_busy  = 0;
      end
      START: begin
        n_busy = 1;
        if (uif_r.btick) begin
          if (c_tickcnt == OSR / 2 - 1) begin
            n_tickcnt = 0;
            n_state   = DATA;
          end else begin
            n_tickcnt = c_tickcnt + 1;
          end
        end
      end
      DATA: begin
        if (uif_r.btick) begin
          if (c_tickcnt == OSR - 1) begin
            n_tickcnt = 0;
            n_data = {uif_r.rx, c_data[7:1]};
            if (c_bitcnt == DATALEN - 1) begin
              n_bitcnt = 0;
              n_state  = STOP;
            end else begin
              n_bitcnt = c_bitcnt + 1;
            end
          end else begin
            n_tickcnt = c_tickcnt + 1;
          end
        end
      end
      STOP: begin
        if (uif_r.btick) begin
          if (c_tickcnt == OSR - 1) begin
            n_tickcnt = 0;
            n_state = IDLE;
            n_done = 1;
            n_busy = 0;
          end else begin
            n_tickcnt = c_tickcnt + 1;
          end
        end
      end
    endcase
  end
endmodule
module uart_bdgen (
    uart_if.bdgen uif_b
);
  logic [15:0] COUNT_LIMIT;
  logic [15:0] r_count;
  wire rst = uif_b.rst;
  wire clk = uif_b.clk;
  wire btick = (r_count == COUNT_LIMIT - 1);
  assign COUNT_LIMIT = uif_b.divisor;
  assign uif_b.btick = btick;

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      r_count <= 0;
    end else begin
      if (COUNT_LIMIT != 0) begin
        if (r_count == COUNT_LIMIT - 1) begin
          r_count <= 0;
        end else begin
          r_count <= r_count + 1;
        end
      end
    end
  end
endmodule
