// tb_advanced.sv
// Testbench for APB-UART with cross coverage for divisor and data.
// Advanced version: Driver sends data until TX FIFO is full, scoreboard manages expected data queue.

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

// Transaction class to hold randomized values
class uart_transaction;
  rand logic [ 7:0] wdata_q[$]; // Changed to a queue of bytes
  rand logic [15:0] divisor;

  // Constraint for 4 specific divisor values for different baud rates
  // Assuming SYS_FREQ = 100MHz, OVS = 16
  // 9600 bps: divisor = 651
  // 19200 bps: divisor = 326
  // 38400 bps: divisor = 163
  // 115200 bps: divisor = 54
  constraint divisor_c {divisor inside {651, 326, 163, 54};}
  constraint wdata_q_size_c { wdata_q.size() inside {[1:16]}; } // Randomize queue size, e.g., up to 16 bytes (typical FIFO depth)
  constraint wdata_q_content_c { foreach (wdata_q[i]) wdata_q[i] inside {[0:255]}; } // Randomize content
endclass

// Generator to create and randomize transactions
class generator;
  mailbox #(uart_transaction) gen_to_drv_mbx;
  uart_transaction tr;
  event scb_done_event;  // Changed from drv_done
  int repeat_count = 4 * 10;  // Test 4 divisors * 10 bursts (adjust as needed)

  function new(mailbox#(uart_transaction) mbx, event scb_done_event);  // Added event to constructor
    this.gen_to_drv_mbx = mbx;
    this.scb_done_event = scb_done_event;  // Assigned event
  endfunction

  task run();
    repeat (repeat_count) begin
      tr = new();
      if (!tr.randomize()) begin
        $error("[GEN] Transaction randomization failed!");
      end
      gen_to_drv_mbx.put(tr);
      $display("[GEN] Transaction (burst size %0d) has put to mailbox", tr.wdata_q.size());
      @(scb_done_event);  // Changed from drv_done
    end
    $display("[%0t] [GEN] All transactions have been generated.", $time);
  endtask
endclass

// Driver to drive APB signals based on the transaction
class driver;
  mailbox #(uart_transaction) gen_to_drv_mbx;
  mailbox #(uart_transaction) drv_to_scb_mbx; // For divisor and original transaction
  mailbox #(logic [7:0]) drv_to_scb_data_mbx; // For individual sent bytes
  mailbox #(apb_transaction) apb_request_mbx;  // New: Mailbox to APB Master Agent
  uart_transaction tr;

  function new(mailbox#(uart_transaction) gen_to_drv_mbx, mailbox#(uart_transaction) drv_to_scb_mbx,
               mailbox#(logic [7:0]) drv_to_scb_data_mbx, mailbox#(apb_transaction) apb_request_mbx);  // Modified constructor
    this.gen_to_drv_mbx  = gen_to_drv_mbx;
    this.drv_to_scb_mbx  = drv_to_scb_mbx;
    this.drv_to_scb_data_mbx = drv_to_scb_data_mbx;
    this.apb_request_mbx = apb_request_mbx;  // Assign new mailbox
  endfunction

  task run();
    forever begin
      gen_to_drv_mbx.get(tr);
      $display("[%0t] [DRV] Starting transaction for divisor=%0d, burst size=%0d", $time, tr.divisor,
               tr.wdata_q.size());

      // 1. Set Divisor via APB
      set_divisor(tr.divisor);

      // 2. Send data burst via APB, polling LSR[5]
      foreach (tr.wdata_q[i]) begin
        wait_for_thr_empty(); // Wait until TX FIFO is not full
        send_data(tr.wdata_q[i]);
        drv_to_scb_data_mbx.put(tr.wdata_q[i]); // Send individual byte to scoreboard
      end

      // 3. Pass original transaction (with divisor and full data queue) to scoreboard for checking
      drv_to_scb_mbx.put(tr);
    end
  endtask

  // Task to send APB write request
  task send_apb_write_request(logic [31:0] addr, logic [31:0] data);
    apb_transaction apb_tr = new(1, addr, data);
    apb_request_mbx.put(apb_tr);
  endtask

  // Task to send APB read request and get response
  task automatic send_apb_read_request(logic [31:0] addr, output logic [31:0] rdata);
    apb_transaction apb_tr = new(0, addr);
    apb_request_mbx.put(apb_tr);
    apb_tr.response_mbx.get(rdata);
  endtask

  // Task to set the baud rate divisor
  task set_divisor(logic [15:0] divisor_val);
    logic [7:0] dll = divisor_val[7:0];
    logic [7:0] dlh = divisor_val[15:8];

    send_apb_write_request(LCR_ADDR, 32'h80);  // Set DLAB = 1
    send_apb_write_request(DLL_ADDR, {24'h0, dll});  // Write DLL
    send_apb_write_request(DLH_ADDR, {24'h0, dlh});  // Write DLH
    send_apb_write_request(LCR_ADDR, 32'h03);  // Set DLAB = 0, 8-bit word length
  endtask

  // Task to send data to be transmitted
  task send_data(logic [7:0] data);
    send_apb_write_request(THR_ADDR, {24'h0, data});
  endtask

  // Task to poll LSR[5] until THR is empty (TX FIFO not full)
  task wait_for_thr_empty();
    logic [31:0] lsr_data_32;
    logic thr_empty = 0;
    while (!thr_empty) begin
      send_apb_read_request(LSR_ADDR, lsr_data_32);
      thr_empty = lsr_data_32[5]; // Check LSR[5] for THR Empty
      if (!thr_empty) begin
        repeat (10) @(posedge apb_request_mbx.aif.PCLK); // Wait before polling again
      end
    end
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
  mailbox #(uart_transaction) drv_to_scb_mbx; // For divisor and original transaction
  mailbox #(logic [7:0]) drv_to_scb_data_mbx; // For individual sent bytes
  mailbox #(logic [7:0]) mon_to_scb_mbx;
  event coverage_done;  // This is for overall coverage completion
  event scb_done_event;  // Added for transaction-level synchronization

  logic [7:0] expected_data_q[$]; // Queue to store expected data bytes
  uart_transaction current_tr;

  int pass_count = 0;
  int fail_count = 0;
  int total_count = 0;

  // Coverage Group for cross coverage
  covergroup uart_cross_coverage with function sample (logic [15:0] d, logic [7:0] v);
    option.per_instance = 1;
    DIVISOR_CP: coverpoint d {bins divisors[] = {651, 326, 163, 54};}
    DATA_CP: coverpoint v {bins data[256] = {[0 : 255]};}
    DIV_X_DATA: cross DIVISOR_CP, DATA_CP;
  endgroup

  function new(mailbox#(uart_transaction) drv_to_scb_mbx, mailbox#(logic [7:0]) drv_to_scb_data_mbx,
               mailbox#(logic [7:0]) mon_to_scb_mbx, event scb_done_event);  // Modified constructor
    this.drv_to_scb_mbx = drv_to_scb_mbx;
    this.drv_to_scb_data_mbx = drv_to_scb_data_mbx;
    this.mon_to_scb_mbx = mon_to_scb_mbx;
    this.scb_done_event = scb_done_event;  // Assigned event
    this.uart_cross_coverage = new();
  endfunction

  task run();
    logic [7:0] received_byte;
    logic [7:0] expected_byte;
    forever begin
      // Wait for a received byte
      mon_to_scb_mbx.get(received_byte); // This will block until a byte is received

      // Now, check if we have expected data for this received byte
      if (expected_data_q.size() == 0) begin
        // If expected_data_q is empty, we MUST have a new burst transaction pending
        // from the driver that hasn't been processed yet.
        // We need to get the next burst transaction from the driver first.
        drv_to_scb_mbx.get(current_tr); // This will block until a new burst is sent
        foreach (current_tr.wdata_q[i]) begin
          expected_data_q.push_back(current_tr.wdata_q[i]);
        end
      end

      // Now expected_data_q should not be empty (unless there's a bug)
      expected_byte = expected_data_q.pop_front();

      total_count++;
      if (expected_byte == received_byte) begin
        pass_count++;
        $display("[%0t] [SCB] PASS: Expected 0x%0h, Got 0x%0h (Divisor: %0d)", $time, expected_byte,
                 received_byte, current_tr.divisor);
      end else begin
        fail_count++;
        $error("********** [%0t] [SCB] FAIL: Expected 0x%0h, Got 0x%0h (Divisor: %0d) **********", $time, expected_byte,
               received_byte, current_tr.divisor);
      end

      // Sample coverage for each byte
      uart_cross_coverage.sample(current_tr.divisor, received_byte);
      $display("[%0t] [SCB] Coverage: %.2f%%", $time, uart_cross_coverage.get_inst_coverage());

      // Trigger scb_done_event when the current burst is fully verified
      if (expected_data_q.size() == 0) begin
        ->scb_done_event;  // Signal after each burst verification
      end

      if (uart_cross_coverage.get_inst_coverage() >= 100.0) begin
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
    $display("= TOTAL COUNT: %0d", total_count);
    $display("=========================================");
  endtask
endclass

// Top-level testbench module
module tb_advanced;
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
  mailbox #(uart_transaction) drv_to_scb_mbx = new(); // For divisor and original transaction
  mailbox #(logic [7:0]) drv_to_scb_data_mbx = new(); // For individual sent bytes
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

    drv = new(gen_to_drv_mbx, drv_to_scb_mbx, drv_to_scb_data_mbx, apb_request_mbx);  // Pass apb_request_mbx

    mon = new(aif, mon_to_scb_mbx, apb_request_mbx);  // Pass apb_request_mbx
    scb = new(drv_to_scb_mbx, drv_to_scb_data_mbx, mon_to_scb_mbx, scb_done_event);  // Pass scb_done_event
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
    $dumpfile("tb_advanced_waves.vcd");
    $dumpvars(0, tb_advanced);
  end

endmodule
