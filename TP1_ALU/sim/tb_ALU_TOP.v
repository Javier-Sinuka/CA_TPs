`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09/01/2026 11:05:23 AM
// Design Name: 
// Module Name: tb_ALU_TOP
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module TestBench_TOP;
  // Parameters for data length
  parameter DATA_LEN = 8;
  parameter OP_LEN = 6;

  // Testbench registers to drive the inputs
  reg [DATA_LEN-1:0] tb_bus = 0;
  reg tb_button_1 = 0;
  reg tb_button_2 = 0;
  reg tb_button_3 = 0;
  reg tb_clock = 0;
  reg tb_reset = 0;

  // Output wire to capture the LED outputs from the DUT (Device Under Test)
  wire [DATA_LEN-1:0] tb_led;
  wire tb_test_led;

  // Instantiate the TOP module
  ALU_top #(
    .DATA_LEN(DATA_LEN),
    .OP_LEN(OP_LEN)
  ) dut (
    .button_1(tb_button_1),
    .button_2(tb_button_2),
    .button_3(tb_button_3),
    .clock(tb_clock),
    .reset(tb_reset),
    .bus(tb_bus),
    .led(tb_led),
    .test_led(tb_test_led)
  );

  // Localparam for ALU operations
    localparam ADD = 6'b100000;
    localparam SUB = 6'b100010;
    localparam AND = 6'b100100;
    localparam OR  = 6'b100101;
    localparam XOR = 6'b100110;
    localparam SRA = 6'b000011;
    localparam SRL = 6'b000010;
    localparam NOR = 6'b100111;

  // Clock generation
  always #5 tb_clock = ~tb_clock; // 10ns clock period

 // Initial block for test sequence
  initial begin
    // Monitor outputs to see changes during simulation
    $monitor("Time = %0t | A = %d | B = %d | OP = %b | LED = %b", 
             $time, dut.reg_data_A, dut.reg_data_B, dut.reg_op, tb_led);

    // Reset the system
    tb_reset = 1;
    #20;
    tb_reset = 0;
    #20;

    // Test 1: ADD operation (1 + 1)
    tb_bus = 8'd1;  // Load 1 into reg_data_A
    tb_button_1 = 1;
    #20;
    tb_button_1 = 0;
    #20;

    tb_bus = 8'd1;  // Load 1 into reg_data_B
    tb_button_2 = 1;
    #20;
    tb_button_2 = 0;
    #20;

    tb_bus = ADD;   // Set operation to ADD
    tb_button_3 = 1;
    #20;
    tb_button_3 = 0;
    #100;

    // Display result after ADD operation
    $display("ADD Operation Result: %b (Expected: 00000010)", tb_led);

    // Test 2: SUB operation (1 - 1)
    tb_bus = SUB;   // Set operation to SUB
    tb_button_3 = 1;
    #20;
    tb_button_3 = 0;
    #100;

    // Display result after SUB operation
    $display("SUB Operation Result: %b (Expected: 00000000)", tb_led);

    // Test 3: AND operation (1 & 1)
    tb_bus = AND;   // Set operation to AND
    tb_button_3 = 1;
    #20;
    tb_button_3 = 0;
    #100;

    // Display result after AND operation
    $display("AND Operation Result: %b (Expected: 00000001)", tb_led);

    // End simulation
    $finish;
  end
endmodule