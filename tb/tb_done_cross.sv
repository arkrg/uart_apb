// tb_cross.sv
// Testbench for APB-UART with cross coverage for divisor and data.

// Using items from packages
import apb_pkg::*;
import uart_pkg::*;

// APB Transaction class for requests to the APB Master Agent
class apb_transaction;
  rand logic                     is_write;
  rand logic              [31:0] addr;
  rand logic              [31:0] wdata;
  logic                   [31:0] rdata;
  mailbox #(logic [31:0])        response_mbx;  // For read responses

  function new(bit is_write, logic [31:0] addr, logic [31:0] wdata = '0);
    this.is_write = is_write;
    this.addr = addr;
    this.wdata = wdata;
    if (!is_write) begin
      response_mbx = new();
    end
  endfunction
endclass

// APB Master Agent to arbitrate and drive the APB interface
class apb_master_agent;
  virtual apb_if.requester   aif;
  mailbox #(apb_transaction) request_mbx;

  function new(virtual apb_if.requester aif, mailbox#(apb_transaction) request_mbx);
    this.aif = aif;
    this.request_mbx = request_mbx;
  endfunction

  task run();
    apb_transaction tr;
    forever begin
      request_mbx.get(tr);
      if (tr.is_write) begin
        apb_write(tr.addr, tr.wdata);
      end else begin
        apb_read(tr.addr, tr.rdata);
        tr.response_mbx.put(tr.rdata);
      end
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

  // APB read task
  task apb_read(logic [31:0] addr, output logic [31:0] data);
    @(posedge aif.PCLK);
    aif.PADDR <= addr;
    aif.PWRITE <= 0;
    aif.PSEL <= 1;
    aif.PENABLE <= 0;
    @(posedge aif.PCLK);
    aif.PENABLE <= 1;
    wait (aif.PREADY);
    data = aif.PRDATA;
    @(posedge aif.PCLK);
    aif.PSEL <= 0;
    aif.PENABLE <= 0;
  endtask
endclass

// // Transaction class to hold randomized values
class uart_transaction;
  rand logic [ 7:0] wdata;
  rand logic [15:0] divisor;

  // Constraint for 4 specific divisor values for different baud rates
  // Assuming SYS_FREQ = 100MHz, OVS = 16
  // 9600 bps: divisor = 651
  // 19200 bps: divisor = 326
  // 38400 bps: divisor = 163
  // 115200 bps: divisor = 54
endclass
//
// Generator to create and randomize transactions
class generator;
  mailbox #(uart_transaction) gen_to_drv_mbx;
  uart_transaction tr;
  event scb_done_event;
  int repeat_count = 4 * 256;  // Still the total number of unique combinations

  // Queue to hold all unique combinations
  uart_transaction unique_combinations_q[$];

  function new(mailbox#(uart_transaction) mbx, event scb_done_event);
    this.gen_to_drv_mbx = mbx;
    this.scb_done_event = scb_done_event;
    build_unique_combinations();  // Populate the queue
    shuffle_combinations();  // Shuffle for randomness
  endfunction

  // Task to build all unique combinations
  function void build_unique_combinations();
    logic [15:0] divisors[] = {651, 326, 163, 54};  // From uart_transaction constraint
    foreach (divisors[d_idx]) begin
      for (int wdata_val = 0; wdata_val < 256; wdata_val++) begin
        uart_transaction new_tr = new();
        new_tr.divisor = divisors[d_idx];
        new_tr.wdata   = wdata_val;
        unique_combinations_q.push_back(new_tr);
      end
    end
    $display("[GEN] Built %0d unique combinations.", unique_combinations_q.size());
  endfunction

  // Task to shuffle the combinations queue
  function void shuffle_combinations();
    for (int i = 0; i < unique_combinations_q.size(); i++) begin
      int j = $urandom_range(0, unique_combinations_q.size() - 1);
      // Swap elements
      uart_transaction temp_tr = unique_combinations_q[i];
      unique_combinations_q[i] = unique_combinations_q[j];
      unique_combinations_q[j] = temp_tr;
    end
    $display("[GEN] Shuffled unique combinations queue.");
  endfunction

  task run();
    repeat (repeat_count) begin  // Iterate exactly repeat_count times
      if (unique_combinations_q.size() == 0) begin
        $error("[GEN] Unique combinations queue is empty prematurely!");
        break;
      end
      tr = unique_combinations_q.pop_front();  // Get a unique combination
      gen_to_drv_mbx.put(tr);
      $display("[GEN] Transaction (divisor=%0d, wdata=0x%0h) put to mailbox.", tr.divisor,
               tr.wdata);
      @(scb_done_event);
    end
    $display("[%0t] [GEN] All unique transactions have been generated.", $time);
  endtask
endclass

// Driver to drive APB signals based on the transaction
class driver;
  mailbox #(uart_transaction) gen_to_drv_mbx;
  mailbox #(uart_transaction) drv_to_scb_mbx;
  mailbox #(apb_transaction) apb_request_mbx;  // New: Mailbox to APB Master Agent
  uart_transaction tr;

  function new(mailbox#(uart_transaction) gen_to_drv_mbx, mailbox#(uart_transaction) drv_to_scb_mbx,
               mailbox#(apb_transaction) apb_request_mbx);  // Modified constructor
    this.gen_to_drv_mbx  = gen_to_drv_mbx;
    this.drv_to_scb_mbx  = drv_to_scb_mbx;
    this.apb_request_mbx = apb_request_mbx;  // Assign new mailbox
  endfunction

  task run();
    forever begin
      ;
      gen_to_drv_mbx.get(tr);
      $display("[%0t] [DRV] Starting transaction for divisor=%0d, data=0x%0h", $time, tr.divisor,
               tr.wdata);

      // 1. Set Divisor via APB
      set_divisor(tr.divisor);

      // 2. Send data via APB
      send_data(tr.wdata);

      // 3. Pass transaction to scoreboard for checking
      drv_to_scb_mbx.put(tr);
    end
  endtask

  // Task to send APB write request
  task send_apb_write_request(logic [31:0] addr, logic [31:0] data);
    apb_transaction apb_tr = new(1, addr, data);
    apb_request_mbx.put(apb_tr);
  endtask

  // Task to set the baud rate divisor
  task set_divisor(logic [15:0] divisor_val);
    logic [7:0] dll = divisor_val[7:0];
    logic [7:0] dlh = divisor_val[15:8];

    send_apb_write_request(LCR_ADDR, 32'h80);  // Set DLAB = 1
    $display("[%0t] [DRV] DLAB asserted to access DL", $time);
    send_apb_write_request(DLL_ADDR, {24'h0, dll});  // Write DLL
    send_apb_write_request(DLH_ADDR, {24'h0, dlh});  // Write DLH
    $display("[%0t] [DRV] DIV has set to new value", $time);
    send_apb_write_request(LCR_ADDR, 32'h03);  // Set DLAB = 0, 8-bit word length
    $display("[%0t] [DRV] DLAB has released", $time);
  endtask

  // Task to send data to be transmitted
  task send_data(logic [7:0] data);
    send_apb_write_request(THR_ADDR, {24'h0, data});
  endtask
endclass

// Monitor to observe APB and capture received data
class monitor;

  virtual apb_if aif;
  mailbox #(logic [7:0]) mon_to_scb_mbx;
  mailbox #(apb_transaction) apb_request_mbx;  // New: Mailbox to APB Master Agent

  function new(virtual apb_if aif, mailbox#(logic [7:0]) mbx,
               mailbox#(apb_transaction) apb_request_mbx);  // Modified constructor
    this.aif = aif;
    this.mon_to_scb_mbx = mbx;
    this.apb_request_mbx = apb_request_mbx;  // Assign new mailbox
  endfunction

  task run();
    logic [ 7:0] received_data;
    logic [31:0] temp_rdata;  // Temporary variable to hold 32-bit read data
    forever begin
      // Wait for Data Ready bit in Line Status Register (LSR[0])
      wait_for_data_ready();

      // Read received data from Receiver Buffer Register (RBR)
      send_apb_read_request(RBR_ADDR, temp_rdata);
      received_data = temp_rdata[7:0];  // Assign the relevant bits
      $display("[%0t] [MON] Received data 0x%0h", $time, received_data);
      mon_to_scb_mbx.put(received_data);
    end
  endtask

  // Task to send APB read request and get response
  task automatic send_apb_read_request(logic [31:0] addr, output logic [31:0] rdata);
    apb_transaction apb_tr = new(0, addr);
    apb_request_mbx.put(apb_tr);
    apb_tr.response_mbx.get(rdata);
  endtask

  // Task to poll LSR until data is ready
  task wait_for_data_ready();
    logic [31:0] lsr_data_32;
    logic data_ready = 0;
    while (!data_ready) begin
      send_apb_read_request(LSR_ADDR, lsr_data_32);
      data_ready = lsr_data_32[0];
      if (!data_ready) begin
        repeat (10) @(posedge aif.PCLK);  // Wait before polling again
      end
    end
  endtask
endclass

// Scoreboard to verify data and collect coverage
class scoreboard;
  mailbox #(uart_transaction) drv_to_scb_mbx;
  mailbox #(logic [7:0]) mon_to_scb_mbx;
  event coverage_done;  // This is for overall coverage completion
  event scb_done_event;  // Added for transaction-level synchronization

  int pass_count = 0;
  int fail_count = 0;
  int total_count = 0;

  // Coverage Group for cross coverage
  covergroup uart_cross_coverage with function sample (logic [15:0] d, logic [7:0] v);
    option.per_instance = 1;
    DIVISOR_CP: coverpoint d {bins divisors[] = {651, 326};}
    DATA_CP: coverpoint v {bins data[] = {[0 : 127]};}
    DIV_X_DATA: cross DIVISOR_CP, DATA_CP;
  endgroup

  function new(mailbox#(uart_transaction) drv_to_scb_mbx, mailbox#(logic [7:0]) mon_to_scb_mbx,
               event scb_done_event);  // Added event to constructor
    this.drv_to_scb_mbx = drv_to_scb_mbx;
    this.mon_to_scb_mbx = mon_to_scb_mbx;
    this.scb_done_event = scb_done_event;  // Assigned event
    this.uart_cross_coverage = new();
  endfunction

  task run();
    uart_transaction expected_tr;
    logic [7:0] actual_data;
    forever begin
      drv_to_scb_mbx.get(expected_tr);
      mon_to_scb_mbx.get(actual_data);
      total_count++;
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

      if (uart_cross_coverage.get_inst_coverage() >= 100.0) begin
        ->coverage_done;
      end
      ->scb_done_event;  // Signal after each transaction verification
    end
  endtask

  task final_report();
    $display("=========================================");
    $display("=           FINAL TEST REPORT           =");
    $display("=========================================");
    $display("= PASS COUNT: %0d", pass_count);
    $display("= FAIL COUNT: %0d", fail_count);
    $display("= COVERAGE  : %.2f%%", uart_cross_coverage.get_inst_coverage());
    $display("= TOTAL COUNT: %0d", total_count);
    $display("=========================================");
  endtask
endclass

// Top-level testbench module
module tb_cross;
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
  apb_master_agent apb_agent;  // New: APB Master Agent

  // Mailboxes
  mailbox #(uart_transaction) gen_to_drv_mbx = new();
  mailbox #(uart_transaction) drv_to_scb_mbx = new();
  mailbox #(logic [7:0]) mon_to_scb_mbx = new();
  mailbox #(apb_transaction) apb_request_mbx = new();  // New mailbox

  // Events
  event scb_done_event;  // Changed from drv_done
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
    gen = new(gen_to_drv_mbx, scb_done_event);  // Pass scb_done_event
    drv = new(gen_to_drv_mbx, drv_to_scb_mbx, apb_request_mbx);  // Corrected to 3 arguments
    mon = new(aif, mon_to_scb_mbx, apb_request_mbx);  // Corrected to 2 arguments
    scb = new(drv_to_scb_mbx, mon_to_scb_mbx, scb_done_event);  // Pass scb_done_event
    scb.coverage_done = coverage_done;
    apb_agent = new(aif.requester, apb_request_mbx);  // Instantiate APB Master Agent

    // Fork processes
    fork
      gen.run();
      drv.run();
      mon.run();
      scb.run();
      apb_agent.run();  // Start APB Master Agent
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
        #1_000_000_000;  // Timeout to prevent infinite simulation
        $error("Test timed out!");
      end
    join_any

    scb.final_report();
    $finish;
  end

  // Waveform dumping
  initial begin
    $dumpfile("tb_cross_waves.vcd");
    $dumpvars(0, tb_cross);
  end

endmodule
