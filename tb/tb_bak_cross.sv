
// tb_cross.sv
// Testbench for APB-UART with cross coverage for divisor and data.

// Using items from packages
import apb_pkg::*;
import uart_pkg::*;

// Transaction class to hold randomized values
class uart_transaction;
  rand logic [ 7:0] wdata;
  rand logic [15:0] divisor;

  // Constraint for 4 specific divisor values for different baud rates
  // Assuming SYS_FREQ = 100MHz, OVS = 16
  // 9600 bps: divisor = 651
  // 19200 bps: divisor = 326
  // 38400 bps: divisor = 163
  // 115200 bps: divisor = 54
  constraint divisor_c {divisor inside {651, 326, 163, 54};}
endclass

// Generator to create and randomize transactions
class generator;
  mailbox #(uart_transaction) gen_to_drv_mbx;
  uart_transaction tr;
  event drv_done;
  int repeat_count = 4 * 256;  // Test all combinations

  function new(mailbox#(uart_transaction) mbx);
    this.gen_to_drv_mbx = mbx;
  endfunction

  task run();
    repeat (repeat_count) begin
      tr = new();
      if (!tr.randomize()) begin
        $error("[GEN] Transaction randomization failed!");
      end
      gen_to_drv_mbx.put(tr);
      $display("[GEN] Transaction has put to mailbox");
      @(drv_done);
    end
    $display("[%0t] [GEN] All transactions have been generated.", $time);
  endtask
endclass

// Driver to drive APB signals based on the transaction
class driver;
  virtual apb_if.requester aif;
  mailbox #(uart_transaction) gen_to_drv_mbx;
  mailbox #(uart_transaction) drv_to_scb_mbx;
  uart_transaction tr;
  event drv_done;

  function new(virtual apb_if.requester aif, mailbox#(uart_transaction) gen_to_drv_mbx,
               mailbox#(uart_transaction) drv_to_scb_mbx);
    this.aif = aif;
    this.gen_to_drv_mbx = gen_to_drv_mbx;
    this.drv_to_scb_mbx = drv_to_scb_mbx;
  endfunction

  task run();
    forever begin
      gen_to_drv_mbx.get(tr);
      $display("[%0t] [DRV] Starting transaction for divisor=%0d, data=0x%0h", $time, tr.divisor,
               tr.wdata);

      // 1. Set Divisor via APB
      set_divisor(tr.divisor);

      // 2. Send data via APB
      send_data(tr.wdata);

      // 3. Pass transaction to scoreboard for checking
      drv_to_scb_mbx.put(tr);

      // 4. Signal generator to create the next transaction
      ->drv_done;
    end
  endtask

  // APB write task
  task apb_write(logic [31:0] addr, logic [31:0] data);
    @(posedge aif.PCLK);
    aif.PADDR <= addr;
    aif.PWRITE <= 1;
    aif.PWDATA <= data;
    aif.PSEL <= 1;
    aif.PENABLE <= 0;
    @(posedge aif.PCLK);
    aif.PENABLE <= 1;
    wait (aif.PREADY);
    @(posedge aif.PCLK);
    aif.PSEL <= 0;
    aif.PENABLE <= 0;
  endtask

  // Task to set the baud rate divisor
  task set_divisor(logic [15:0] divisor_val);
    logic [7:0] dll = divisor_val[7:0];
    logic [7:0] dlh = divisor_val[15:8];

    apb_write(LCR_ADDR, 32'h80);  // Set DLAB = 1
    $display("[%0t] [DRV] DLAB asserted to access DL", $time);
    apb_write(DLL_ADDR, {24'h0, dll});  // Write DLL
    apb_write(DLH_ADDR, {24'h0, dlh});  // Write DLH
    $display("[%0t] [DRV] DIV has set to new value", $time);
    apb_write(LCR_ADDR, 32'h03);  // Set DLAB = 0, 8-bit word length
    $display("[%0t] [DRV] DLAB has released", $time);
  endtask

  // Task to send data to be transmitted
  task send_data(logic [7:0] data);
    // Wait until Transmitter Holding Register is empty (LSR[5] == 1)
    // This is a simple polling mechanism. A real scenario might use interrupts.
    // For this loopback test, we can assume it's ready for the first write.
    apb_write(THR_ADDR, {24'h0, data});
  endtask
endclass

// Monitor to observe APB and capture received data
class monitor;
  virtual apb_if.requester aif;
  mailbox #(logic [7:0]) mon_to_scb_mbx;

  function new(virtual apb_if.requester aif, mailbox#(logic [7:0]) mbx);
    this.aif = aif;
    this.mon_to_scb_mbx = mbx;
  endfunction

  task run();
    logic [7:0] received_data;
    forever begin
      // Wait for Data Ready bit in Line Status Register (LSR[0])
      wait_for_data_ready();

      // Read received data from Receiver Buffer Register (RBR)
      apb_read(RBR_ADDR, received_data);
      $display("[%0t] [MON] Received data 0x%0h", $time, received_data);
      mon_to_scb_mbx.put(received_data);
    end
  endtask

  // APB read task
  task apb_read(logic [31:0] addr, output logic [7:0] data);
    logic [31:0] read_data;
    @(posedge aif.PCLK);
    aif.PADDR <= addr;
    aif.PWRITE <= 0;
    aif.PSEL <= 1;
    aif.PENABLE <= 0;
    @(posedge aif.PCLK);
    aif.PENABLE <= 1;
    wait (aif.PREADY);
    read_data = aif.PRDATA;
    @(posedge aif.PCLK);
    aif.PSEL <= 0;
    aif.PENABLE <= 0;
    data = read_data[7:0];
  endtask

  // Task to poll LSR until data is ready
  task wait_for_data_ready();
    logic [7:0] lsr_data;
    logic data_ready = 0;
    while (!data_ready) begin
      apb_read(LSR_ADDR, lsr_data);
      data_ready = lsr_data[0];
      if (!data_ready) begin
        repeat (10) @(posedge aif.PCLK);  // Wait before polling again
      end
    end
    $display("%t inter of wait for ready", $time);
    $display("%d ready", data_ready);
  endtask
endclass

// Scoreboard to verify data and collect coverage
class scoreboard;
  mailbox #(uart_transaction) drv_to_scb_mbx;
  mailbox #(logic [7:0]) mon_to_scb_mbx;
  event coverage_done;

  int pass_count = 0;
  int fail_count = 0;

  // Coverage Group for cross coverage
  covergroup uart_cross_coverage with function sample (logic [15:0] d, logic [7:0] v);
    option.per_instance = 1;
    DIVISOR_CP: coverpoint d {bins divisors[] = {651, 326, 163, 54};}
    DATA_CP: coverpoint v {bins data[256] = {[0 : 255]};}
    DIV_X_DATA: cross DIVISOR_CP, DATA_CP;
  endgroup

  function new(mailbox#(uart_transaction) drv_to_scb_mbx, mailbox#(logic [7:0]) mon_to_scb_mbx);
    this.drv_to_scb_mbx = drv_to_scb_mbx;
    this.mon_to_scb_mbx = mon_to_scb_mbx;
    this.uart_cross_coverage = new();
  endfunction

  task run();
    uart_transaction expected_tr;
    logic [7:0] actual_data;
    forever begin
      drv_to_scb_mbx.get(expected_tr);
      mon_to_scb_mbx.get(actual_data);

      if (expected_tr.wdata == actual_data) begin
        pass_count++;
        $display("[%0t] [SCB] PASS: Expected 0x%0h, Got 0x%0h", $time, expected_tr.wdata,
                 actual_data);
      end else begin
        fail_count++;
        $error("[%0t] [SCB] FAIL: Expected 0x%0h, Got 0x%0h", $time, expected_tr.wdata,
               actual_data);
      end

      // Sample coverage
      uart_cross_coverage.sample(expected_tr.divisor, actual_data);
      $display("[%0t] [SCB] Coverage: %.2f%%", $time, uart_cross_coverage.get_inst_coverage());

      if (uart_cross_coverage.get_inst_coverage() >= 10.0) begin
        ->coverage_done;
      end
    end
  endtask

  task final_report();
    $display("=========================================");
    $display("=           FINAL TEST REPORT           =");
    $display("=========================================");
    $display("= PASS COUNT: %0d", pass_count);
    $display("= FAIL COUNT: %0d", fail_count);
    $display("= COVERAGE  : %.2f%%", uart_cross_coverage.get_inst_coverage());
    $display("=========================================");
  endtask
endclass

// Top-level testbench module
module tb_bak_cross;
  logic clk, reset;

  // APB Interface
  apb_if aif (
      .PCLK(clk),
      .PRESETn(~reset)
  );

  // DUT signals
  logic tx, rx;

  // Loopback connection
  assign rx = tx;

  // Instantiate DUT
  apb_uart_periph dut (
      .apb_c(aif.completer),
      .tx(tx),
      .rx(rx)
  );

  // Verification Environment
  generator gen;
  driver drv;
  monitor mon;
  scoreboard scb;

  // Mailboxes
  mailbox #(uart_transaction) gen_to_drv_mbx = new();
  mailbox #(uart_transaction) drv_to_scb_mbx = new();
  mailbox #(logic [7:0]) mon_to_scb_mbx = new();

  // Events
  event drv_done;
  event coverage_done;

  // Clock and Reset Generation
  initial begin
    clk = 0;
    forever #5 clk = ~clk;  // 100MHz clock
  end

  initial begin
    reset = 0;
    #10;
    reset = 1;
    #20;
    reset = 0;
  end

  // Test execution
  initial begin
    // Create environment components
    gen = new(gen_to_drv_mbx);
    gen.drv_done = drv_done;

    drv = new(aif.requester, gen_to_drv_mbx, drv_to_scb_mbx);
    drv.drv_done = drv_done;

    mon = new(aif.requester, mon_to_scb_mbx);
    scb = new(drv_to_scb_mbx, mon_to_scb_mbx);
    scb.coverage_done = coverage_done;

    // Fork processes
    fork
      gen.run();
      drv.run();
      mon.run();
      scb.run();
    join_none

    // Wait for coverage to be 100% or timeout
    fork
      begin
        @(coverage_done);
        $display("*************************************************");
        $display("*   Cross Coverage is 100%! Test finished.    *");
        $display("*************************************************");
      end
      begin
        #10_000_000;  // Timeout to prevent infinite simulation
        $error("Test timed out!");
      end
    join_any

    scb.final_report();
    $finish;
  end

  // Waveform dumping
  // initial begin
  // $dumpfile("tb_cross_waves.vcd");
  // $dumpvars(0, tb_cross);
  // end

endmodule
