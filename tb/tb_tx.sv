import apb_pkg::*;  // note that package must be compiled first
class apbSignal;
  rand logic [31:0] addr;
  rand logic [31:0] wdata;
  // int               completer_id;
  randc int         completer_id;
  randc int         reg_id;

  // constraint sel_completer_c {completer_id inside {[0 : NUM_COMP - 1]};}
  // constraint sel_reg_c {reg_id inside {[0 : 3]};}
  constraint sel_completer_c {completer_id == 5;}
  constraint sel_reg_c {reg_id inside {[0 : 3]};}
  constraint addr_mapping_c {
    addr[3:2] == reg_id;
    addr % 4 == 0;
  }

  virtual front_if fif;
  function new(virtual front_if fif);
    this.fif = fif;
  endfunction

  task automatic rsend();
    fif.transfer <= 1;
    fif.write    <= 1;
    fif.addr     <= addr;
    fif.wdata    <= wdata;
    @(posedge fif.clk);
    fif.transfer <= 0;
    @(posedge fif.clk);
    wait (fif.ready);
    @(posedge fif.clk);
  endtask  //automatic

  task automatic dsend(logic [31:0] addr, logic [31:0] wdata);
    fif.transfer <= 1;
    fif.write    <= 1;
    fif.addr     <= addr;
    fif.wdata    <= wdata;
    @(posedge fif.clk);
    fif.transfer <= 0;
    @(posedge fif.clk);
    wait (fif.ready);
    @(posedge fif.clk);
  endtask  //automatic

  task automatic recieve(logic [31:0] addr);
    fif.transfer <= 1;
    fif.write    <= 0;
    fif.addr     <= addr;
    @(posedge fif.clk);
    fif.transfer <= 0;
    @(posedge fif.clk);
    wait (fif.ready);
    @(posedge fif.clk);

  endtask  //automatic
endclass
//
class transaction;

endclass
class generator;

endclass
class driver;

endclass

module tb_tx ();
  localparam int SYS_FREQ = 100_000_000;
  localparam int OVS = 16;
  localparam int BRATE = 9600;
  localparam int DIVISOR = SYS_FREQ / OVS / BRATE;

  logic clk, reset;
  logic tx, rx;
  logic [7:0] DLL, DLH;
  wire btick = dut.u_uart.u_uart_core.u_bdgen.btick;

  time t1, t2;
  assign {DLH, DLL} = DIVISOR;

  // interface
  front_if fif (
      .clk,
      .reset
  );
  apb_if aif (
      .PCLK(clk),
      .PRESETn(~reset)
  );
  assign aif.PSELC = aif.PSELR[4];

  apb_requester vip_requester (
      .fif  (fif),
      .aif_r(aif.requester)
  );
  // dut instance
  apb_uart_periph dut (
      .apb_c(aif.completer),
      .rx,
      .tx
  );

  // object instance
  apbSignal apbUART;

  initial begin
    int i;
    apbUART = new(fif);
    repeat (3) @(posedge clk);
    apbUART.dsend(32'h1000_400C, 32'h0000_0080);  // DLAB = 1;
    apbUART.dsend(32'h1000_4004, {24'h0, DLH});  // DLH write;
    apbUART.dsend(32'h1000_4000, {24'h0, DLL});  // DLL write;
    apbUART.dsend(32'h1000_400C, 32'h0000_0000);  // DLAB = 1;
    apbUART.dsend(32'h1000_4000, {24'h0, {24'd0, 8'h0f}});  // DLH write;
    repeat (10 * 16) @(posedge btick);
    #20;
    $finish;
  end

  // essential : initialize, wave dumping
  initial begin
    clk   = 0;
    reset = 1;
    #10;
    reset = 0;
  end
  always #5 clk = ~clk;
  initial begin
    $dumpfile("waves.vcd");
    $dumpvars();
  end
endmodule



