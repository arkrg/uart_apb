import apb_pkg::*;
module apb_completer #(
    parameter int REG_NUM   = 4,
    parameter int SLV_INDEX = 0
) (
    apb_if.completer aif_c
);

  logic                  PCLK;
  logic                  PRESET;
  logic [ADDR_WIDTH-1:0] PADDR;
  logic                  PWRITE;
  logic                  PSEL;
  logic                  PENABLE;
  logic [DATA_WIDTH-1:0] PWDATA;
  logic [DATA_WIDTH-1:0] PRDATA;
  logic                  PREADY;

  logic [DATA_WIDTH-1:0] slv_reg  [REG_NUM];
  logic [DATA_WIDTH-1:0] r_PRDATA;
  logic                  r_PREADY;

  assign PCLK    = aif_c.PCLK   ;
  assign PRESET  = aif_c.PRESET ;
  assign PADDR   = aif_c.PADDR  ;
  assign PWRITE  = aif_c.PWRITE ;
  assign PSEL    = aif_c.PSEL[SLV_INDEX]   ;
  assign PENABLE = aif_c.PENABLE;
  assign PWDATA  = aif_c.PWDATA ;
  assign aif_c.PRDATA  = PRDATA ;
  assign aif_c.PREADY  = PREADY ;


  wire PSEL_AND_PENABLE = PSEL & PENABLE;

  always_ff @(posedge PCLK, posedge PRESET) begin
    if (PRESET) begin
      slv_reg[0] <= 0;
      slv_reg[1] <= 0;
      slv_reg[2] <= 0;
      slv_reg[3] <= 0;

      r_PRDATA   <= 0;
      r_PREADY   <= 0;
    end else begin
      r_PREADY <= 1'b0;
      if (PSEL_AND_PENABLE) begin
        r_PREADY <= 1;
        if (PWRITE) begin
          // WRITE Transaction
          slv_reg[PADDR[3:2]] <= PWDATA;
        end else begin
          // READ Transaction
          r_PRDATA <= slv_reg[PADDR[3:2]];
        end
      end
    end
  end

  assign PREADY = (PSEL_AND_PENABLE) ? r_PREADY : 'bz;
  assign PRDATA = (PSEL_AND_PENABLE & PREADY & ~PWRITE) ? r_PRDATA : 'hz;
endmodule
