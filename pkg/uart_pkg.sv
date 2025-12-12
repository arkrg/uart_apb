package uart_pkg;
  //  localparam int SYS_FREQUENCY = 100_000_000;
  localparam int OSR = 16;
  localparam int DATALEN = 8;

  typedef enum {
    IDLE,
    START,
    DATA,
    STOP
  } states_e;
  // register map
  localparam bit [31:0] LSR_ADDR = 32'h1000_4014;
  localparam bit [31:0] LCR_ADDR = 32'h1000_400C;
  localparam bit [31:0] DLL_ADDR = 32'h1000_4000;
  localparam bit [31:0] DLH_ADDR = 32'h1000_4004;
  localparam bit [31:0] THR_ADDR = 32'h1000_4000;
  localparam bit [31:0] RBR_ADDR = 32'h1000_4000;
endpackage
