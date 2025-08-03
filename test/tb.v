`default_nettype none
`timescale 1ns / 1ps

/* This testbench just instantiates the module and makes some convenient wires
   that can be driven / tested by the cocotb test.py.
*/
module tb ();
    // Dump the signals to a VCD file. You can view it with gtkwave or surfer.
    initial begin
        $dumpfile("tb.vcd");
        $dumpvars(0, tb);
        #1;
    end

    // Wire up the inputs and outputs:
    reg clk;
    reg rst_n;
    reg ena;
    reg [7:0] ui_in;
    reg [7:0] uio_in;
    wire [7:0] uo_out;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;

    // Replace tt_um_example with your module name:
    tt_um_ev_motor_control user_project (
        .ui_in  (ui_in),    // Dedicated inputs
        .uo_out (uo_out),   // Dedicated outputs
        .uio_in (uio_in),   // IOs: Input path
        .uio_out(uio_out),  // IOs: Output path
        .uio_oe (uio_oe),   // IOs: Enable path (active high: 0=input, 1=output)
        .ena    (ena),      // enable - goes high when design is selected
        .clk    (clk),      // clock
        .rst_n  (rst_n)     // not reset
    );

    // Clock generation - 10ns period (100MHz)
    always #5 clk = ~clk;

    // Test stimulus
    initial begin
        // Initialize all signals
        clk = 0;
        rst_n = 0;
        ena = 1;
        ui_in = 8'b0;
        uio_in = 8'b0;

        // Hold reset for some time
        #50;
        rst_n = 1;
        #20;

        $display("=== TinyTapeout EV Motor Control Test Started ===");

        // Test 1: Power Control
        ui_in[2:0] = 3'b000;    // operation_select = power control
        ui_in[3] = 1'b1;        // power_on_plc = 1
        ui_in[4] = 1'b0;        // power_on_hmi = 0
        #30;
        $display("Test 1 - Power ON: %b", uo_out[0]);

        // Test 2: Headlight Control
        ui_in[2:0] = 3'b001;    // operation_select = headlight
        ui_in[6] = 1'b1;        // headlight_plc = 1
        ui_in[7] = 1'b0;        // headlight_hmi = 0
        #30;
        $display("Test 2 - Headlight ON: %b", uo_out[1]);

        // Test 3: Motor Speed Calculation
        ui_in[2:0] = 3'b100;    // operation_select = motor speed
        uio_in[7:4] = 4'd12;    // accelerator = 12
        #20;
        uio_in[7:4] = 4'd4;     // brake = 4
        #30;
        $display("Test 3 - Motor Speed: %d", uio_out);

        // Test 4: PWM Generation
        ui_in[2:0] = 3'b101;    // operation_select = PWM
        #100;
        $display("Test 4 - PWM Signal: %b", uo_out[4]);

        $display("=== Test Completed ===");
        #100;
        $finish;
    end

endmodule
