import apb_pkg::*;  // note that package must be compiled first
class apbSignal;
  rand logic [31:0] addr;
  rand logic [31:0] wdata;
  // int               completer_id;
  randc int         completer_id;
  randc int         reg_id;

  // constraint sel_completer_c {completer_id inside {[0 : NUM_COMP - 1]};}
  // constraint sel_reg_c {reg_id inside {[0 : 3]};}
  constraint er_c {completer_id == 5;}
  constraint sel_reg_c {reg_id inside {[0 : 3]};}
  constraint addr_mapping_c {
    // if (completer_id == 0)
    // addr inside {[32'h1000_0000 : 32'h1000_0FFF]};
    // else
    // if (completer_id == 1)
    // addr inside {[32'h1000_1000 : 32'h1000_1FFF]};
    // else
    // if (completer_id == 2)
    // addr inside {[32'h1000_2000 : 32'h1000_2FFF]};
    // else
    // addr inside {[32'h1000_3000 : 32'h1000_3FFF]};
    addr[3:2] == reg_id;
    addr % 4 == 0;
  }

  virtual front_if fif;
  function new(virtual front_if fif);
    this.fif = fif;
  endfunction

  task automatic rsend();
    apbSignal.randomize();
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
module tb_basic ();
  logic clk, reset;
  logic tx, rx;
  logic [7:0] DLL, DLH;
  localparam int SYS_FREQ = 100_000_000;
  localparam int OVS = 16;
  localparam int BRATE = 9600;
  localparam int DIVISOR = SYS_FREQ / OVS / BRATE;

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
    // for (i = 0; i < 100; i++) begin
    // apbUART.randomize();
    apbUART.send(32'h1000_400C, 32'h0000_0080);  // DLAB = 1;
    apbUART.send(32'h1000_4004, {24'h0, DLH});  // DLH write;
    apbUART.send(32'h1000_4000, {24'h0, DLL});  // DLL write;

    // apbUART.send(32'h1000_400C, 32'h0000_0080);  // DLAB = 1;
    // apbUART.send(32'h1000_4004, {24'h0, DLH});  // DLH write;
    // apbUART.send(32'h1000_4000, {24'h0, DLL});  // DLL write;
    // apbUART.recieve(32'h1000_400C);  // DLAB = 1;
    // end
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


import uart_pkg::*;
class transaction;
  rand logic [DATA_WIDTH-1:0] wdata;
  rand logic [          15:0] divisor;
  logic      [DATA_WIDTH-1:0] rdata;
  logic      [ADDR_WIDTH-1:0] addr;
  logic                       transfer;
  logic                       ready;

  constraint bit8_c {wdata inside {[0 : 2 ** 8 - 1]};}
  constraint divisor_c {divisor inside {9600, 14400, 19200, 38400};}
endclass

class generator;
  transaction trns;
  mailbox #(transaction) gd_mbx;
  event gen_next_event;
  int total_count = 0;
  function new(mailbox#(transaction) mbx, event gen_next_event);
    this.gd_mbx = mbx;
    this.gen_next_event = gen_next_event;
  endfunction

  task genRun();
    forever begin
      total_count++;
      trns = new();
      assert (trns.randomize())
      else $error("[GEN] randomize() error");
      // if (trns.wr) trns.rd = 0;
      gd_mbx.put(trns);
      $display("%t: [GEN] Put randomized data wdata: %c, divisor = %d", $time, trns.wdata,
               trns.divisor);
      $display("%t: [GEN] Wait for gen_next event triggered ", $time);
      @gen_next_event;
      $display("%t: [GEN] Detected gen_next_event triggered ", $time);
    end
  endtask  //genRun
  task genRunfb();
    forever begin
      total_count++;
      trns = new();
      assert (trns.randomize())
      else $error("[GEN] randomize() error");
      // if (trns.wr) trns.rd = 0;
      trns.divisor = 651;
      gd_mbx.put(trns);
      $display("%t: [GEN] Put randomized data wdata: %c, divisor = %d", $time, trns.wdata,
               trns.divisor);
      $display("%t: [GEN] Wait for gen_next event triggered ", $time);
      @gen_next_event;
      $display("%t: [GEN] Detected gen_next_event triggered ", $time);
    end
  endtask  //genRun
endclass

class driver;
  virtual front_if vif;
  transaction trns;
  event mon_next_event, gen_next_event;
  mailbox #(transaction) gd_mbx, ds_mbx;
  function new(mailbox#(transaction) gd_mbx, mailbox#(transaction) ds_mbx, virtual uart_if vif,
               event mon_next_event, event gen_next_event);
    this.gd_mbx = gd_mbx;
    this.ds_mbx = ds_mbx;
    this.vif = vif;
    this.gen_next_event = gen_next_event;
    this.mon_next_event = mon_next_event;
  endfunction  //new()

  task automatic drvRun();
    forever begin
      logic [DATA_WIDTH-1:0] test_data;
      logic [15:0] divisor;
      $display("%t: [DRV] Run phase starts", $time);
      gd_mbx.get(trns);
      ds_mbx.put(trns);
      $display("%t: [DRV] Put data drv-scb mailbox: %b", $time, trns.wdata);
      $display("%t: [DRV] Get data from gen-drv mailbox: %c", $time, trns.wdata);
      vif.rx = 0;
      test_data = trns.wdata;
      $display("%t: [DRV] start sending serial data ", $time);
      repeat (OSR) @(posedge vif.btick);
      repeat (DATALEN) begin
        vif.rx = test_data[0];
        repeat (OSR) @(posedge vif.btick);
        test_data = test_data >> 1;
      end
      vif.rx = 1;
      $display("%t: [DRV] Serial data has transmitted", $time);
      ->mon_next_event;
      $display("%t: [DRV] Triggered mon_next_event", $time);
      @(negedge vif.rx_busy);
      $display("%t: [DRV] Detected falling rx_busy", $time);
      // ->gen_next_event;
      $display("%t: [DRV] Triggered gen_next_event", $time);
      $display("%t: [DRV] finished drvRun", $time);
    end
  endtask
  task automatic dsend(logic [31:0] wdata, logic [31:0] addr);
    fif.transfer <= 1;
    fif.write    <= 1;
    fif.addr     <= addr;
    fif.wdata    <= trns.wdata;
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
endclass  //driver
class monitor;
  transaction trns;
  mailbox #(transaction) ms_mbx;
  virtual uart_if vif;
  event mon_next_event;

  function new(mailbox#(transaction) mbx, virtual uart_if vif, event mon_next_event);
    this.ms_mbx = mbx;
    this.vif = vif;
    this.mon_next_event = mon_next_event;
  endfunction  //new()

  task monRun();
    forever begin
      int i = 0;
      logic [DATALEN-1:0] rec_data;
      transaction trns = new();
      $display("%t: [MON] Wait for mon_next_event", $time);
      @(mon_next_event);
      @(negedge vif.tx);
      $display("%t: [MON] Detected falling edge of tx", $time);
      repeat (OSR / 2) @(posedge vif.btick);
      $display("%t: [MON] Detected TX start signal", $time);
      repeat (DATALEN) begin
        ++i;
        repeat (OSR) @(posedge vif.btick);
        $display("%t: [MON] Sampled %dth data: %d", $time, i, vif.tx);
        rec_data[DATALEN-1] = vif.tx;
        if (i != 8) rec_data = rec_data >> 1;
      end
      $display("%t: [MON] rec_data : %b", $time, rec_data);
      trns.wdata = rec_data;
      ms_mbx.put(trns);
      $display("%t: [MON] rec_data put to mailbox : %c", $time, trns.wdata);
    end
  endtask
endclass  //monitor

class scoreboard;
  transaction trns_ds, trns_ms;
  mailbox #(transaction) ms_mbx, ds_mbx;
  event gen_next_event;
  event done;

  logic [7:0] fifo_queue[$:15];
  logic [7:0] expected_data;
  int pass_count = 0;
  int fail_count = 0;

  logic [DATALEN-1:0] cover_data;
  covergroup ascii_coverage;
    option.per_instance = 1;
    DATA_CP: coverpoint cover_data {bins printable[] = {[32 : 126]};}
  endgroup

  function new(mailbox#(transaction) ms_mbx, mailbox#(transaction) ds_mbx, event gen_next_event,
               event done);
    this.ms_mbx = ms_mbx;
    this.ds_mbx = ds_mbx;
    this.gen_next_event = gen_next_event;
    this.ascii_coverage = new();
    this.done = done;
  endfunction  //new()

  task scbRun();
    forever begin
      ds_mbx.get(trns_ds);
      $display("%t: [SCB] Get DRV data from transaction %c", $time, trns_ds.wdata);
      ms_mbx.get(trns_ms);
      $display("%t: [SCB] Get MON data from transaction ", $time, trns_ms.wdata);
      if (trns_ds.wdata == trns_ms.wdata) begin
        $display("%t: [SCB] *Data matched", $time);
        pass_count++;
        this.cover_data = trns_ms.wdata;
        this.ascii_coverage.sample();
        $display("[SCB] Coverage is now: %f %%", this.ascii_coverage.get_inst_coverage());
        if (this.ascii_coverage.get_inst_coverage() >= 100)->done;
        // ------------------------------------
      end else begin
        $display("%t [SCB] *****FAIL, expected data: %b, rec_data: %b", $time, trns_ds.wdata,
                 trns_ms.wdata);
        fail_count++;
      end
      ->gen_next_event;
      $display("%t: [SCB] gen_next_event triggered", $time);
    end
  endtask  //scb
endclass  //scoreboard 

class enviroment;
  transaction            trns;
  mailbox #(transaction) ms_mbx,         ds_mbx,         gd_mbx;
  event                  gen_next_event, mon_next_event, done;
  virtual uart_if        vif;

  generator              gen;
  driver                 drv;
  monitor                mon;
  scoreboard             scb;

  function new(virtual uart_if vif);
    gd_mbx = new();
    ms_mbx = new();
    ds_mbx = new();
    gen = new(gd_mbx, gen_next_event);
    drv = new(gd_mbx, ds_mbx, vif, mon_next_event, gen_next_event);
    mon = new(ms_mbx, vif, mon_next_event);
    // scb = new(ms_mbx, ds_mbx);
    scb = new(ms_mbx, ds_mbx, gen_next_event, done);
  endfunction  //new()

  task report();
    $display("===============================");
    $display("=         Test report         =");
    $display("===============================");
    $display("      Total Test : %d      ", gen.total_count);
    $display("      Pass Test  : %d      ", scb.pass_count);
    $display("      Fail Test  : %d      ", scb.fail_count);
    $display("===============================");
    $display("==    Test bench is finish   ==");
    $display("===============================");
  endtask  //
  task envRun();
    fork
      begin
        @done;
        begin
          $display("****************************");
          $display("* ASCII Character Coverage 100%% Reached. *");
          $display("****************************");
          #2000;
          report();
          $stop;
        end
      end
      gen.genRun();
      drv.drvRun();
      mon.monRun();
      scb.scbRun();
    join_any
    #10;
    report();
    $display("Finished");
    $stop;
  endtask
endclass  // enviroment

module tb_top_random_cov ();
  logic clk, rst;
  enviroment env;
  uart_if uif (
      .clk,
      .rst
  );

  uart_fifo dut (.uif(uif));
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end
  initial begin
    env = new(uif);
    reset();
    env.envRun();
  end

  initial begin
    $dumpfile("waves.vcd");
    $dumpvars();
  end
  task reset();
    rst = 1;
    repeat (2) @(posedge uif.clk);
    rst = 0;
    repeat (2) @(posedge uif.clk);
    $display("%t: [TOP] Reset phase done", $time);
  endtask
endmodule

