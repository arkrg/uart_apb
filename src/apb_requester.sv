import apb_pkg::*;
module apb_requester (
    apb_if.requester aif_r,
    front_if         fif
);
  logic                  PCLK;
  logic                  PRESETn;
  logic [ADDR_WIDTH-1:0] PADDR;
  logic                  PWRITE;
  logic                  PENABLE;
  logic [DATA_WIDTH-1:0] PWDATA;
  logic [  NUM_COMP-1:0] PSEL;
  logic                  PREADY;
  logic [DATA_WIDTH-1:0] PRDATA;
  logic                  transfer;
  logic                  write;
  logic [ADDR_WIDTH-1:0] addr;
  logic [DATA_WIDTH-1:0] wdata;
  logic [DATA_WIDTH-1:0] rdata;
  logic                  ready;

  assign PCLK          = aif_r.PCLK;
  assign PRESETn       = aif_r.PRESETn;
  assign aif_r.PADDR   = PADDR;
  assign aif_r.PWRITE  = PWRITE;
  assign aif_r.PENABLE = PENABLE;
  assign aif_r.PWDATA  = PWDATA;
  assign aif_r.PSELR   = PSEL;
  assign PREADY        = aif_r.PREADY;
  assign PRDATA        = aif_r.PRDATA;

  assign transfer      = fif.transfer;
  assign write         = fif.write;
  assign addr          = fif.addr;
  assign wdata         = fif.wdata;
  assign rdata         = fif.rdata;
  assign ready         = fif.ready;
  assign fif.rdata     = PRDATA;
  assign fif.ready     = PREADY;

  logic decoder_en;
  logic temp_write_reg, temp_write_next;
  logic [ADDR_WIDTH-1:0] temp_addr_reg, temp_addr_next;
  logic [DATA_WIDTH-1:0] temp_wdata_reg, temp_wdata_next;
  logic [NUM_COMP-1:0] pselx;

  assign PSEL = pselx;

  typedef enum {
    IDLE,
    SETUP,
    ACCESS
  } apb_state_e;

  apb_state_e state, next_state;

  always_ff @(posedge PCLK, negedge PRESETn) begin
    if (!PRESETn) begin
      state          <= IDLE;
      temp_write_reg <= 0;
      temp_addr_reg  <= 0;
      temp_wdata_reg <= 0;
    end else begin
      state          <= next_state;
      temp_write_reg <= temp_write_next;
      temp_addr_reg  <= temp_addr_next;
      temp_wdata_reg <= temp_wdata_next;
    end
  end

  always_comb begin
    next_state      = state;
    temp_write_next = temp_write_reg;
    temp_addr_next  = temp_addr_reg;
    temp_wdata_next = temp_wdata_reg;
    decoder_en      = 1'b0;
    PENABLE         = 1'b0;
    PADDR           = temp_addr_reg;
    PWRITE          = temp_write_reg;
    PWDATA          = temp_wdata_reg;
    case (state)
      IDLE: begin
        decoder_en = 1'b0;
        PWRITE     = 0;
        if (transfer) begin
          next_state      = SETUP;
          temp_write_next = write;
          temp_addr_next  = addr;
          temp_wdata_next = wdata;
        end
      end
      SETUP: begin
        decoder_en = 1'b1;
        PENABLE    = 1'b0;
        PADDR      = temp_addr_reg;
        PWRITE     = temp_write_reg;
        next_state = ACCESS;
        if (temp_write_reg) begin
          PWDATA = temp_wdata_reg;
        end
      end
      ACCESS: begin
        decoder_en = 1'b1;
        PENABLE    = 1'b1;
        if (!transfer & ready) begin
          next_state = IDLE;
        end else if (transfer & ready) begin
          next_state = SETUP;
        end else begin
          next_state = ACCESS;
        end
      end
    endcase
  end

  apb_decoder U_APB_DECODER (
      .en (decoder_en),
      .sel(temp_addr_reg),
      .y  (pselx)
  );


endmodule

module apb_decoder (
    input  logic                  en,
    input  logic [ADDR_WIDTH-1:0] sel,
    output logic [  NUM_COMP-1:0] y
);
  always_comb begin
    y = 'd0;
    if (en) begin
      casex (sel)
        32'h1000_0xxx: y = 'b00001;  // RAM
        32'h1000_1xxx: y = 'b00010;  // P1
        32'h1000_2xxx: y = 'b00100;  // P2
        32'h1000_3xxx: y = 'b01000;  // P3
        32'h1000_4xxx: y = 'b10000;  // P4
      endcase
    end
  end
endmodule
