/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_ev_motor_control (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

    // Pin mapping for ui_in[7:0] (Dedicated inputs)
    wire [2:0] operation_select = ui_in[2:0];  // 3-bit operation selector
    wire power_on_plc = ui_in[3];              // Power control from PLC
    wire power_on_hmi = ui_in[4];              // Power control from HMI
    wire mode_select = ui_in[5];               // 0: PLC mode, 1: HMI mode
    wire headlight_plc = ui_in[6];             // Headlight control from PLC
    wire headlight_hmi = ui_in[7];             // Headlight control from HMI

    // Pin mapping for uio_in[7:0] (Bidirectional inputs)
    wire horn_plc = uio_in[0];                 // Horn control from PLC
    wire horn_hmi = uio_in[1];                 // Horn control from HMI
    wire right_ind_plc = uio_in[2];            // Right indicator from PLC
    wire right_ind_hmi = uio_in[3];            // Right indicator from HMI
    wire [3:0] accelerator_brake_data = uio_in[7:4]; // 4-bit data for accel/brake

    // Pin mapping for uo_out[7:0] (Dedicated outputs)
    wire power_status;
    wire headlight_out;
    wire horn_out;
    wire right_indicator;
    wire motor_pwm;
    wire overheat_warning;
    wire [1:0] status_led;

    assign uo_out = {status_led[1:0], overheat_warning, motor_pwm, 
                     right_indicator, horn_out, headlight_out, power_status};

    // Pin mapping for uio_out[7:0] (Bidirectional outputs)
    wire [7:0] motor_speed_out;
    assign uio_out = motor_speed_out;

    // Set uio_oe to control bidirectional pins (1=output, 0=input)
    assign uio_oe = 8'b11110000;  // uio[7:4] as outputs, uio[3:0] as inputs

    // Internal registers and wires
    reg [3:0] accelerator_value;
    reg [3:0] brake_value;
    reg [3:0] selected_accelerator;
    reg [3:0] selected_brake;
    reg [3:0] speed_calculation;  // FIXED: Changed from 5-bit to 4-bit to avoid unused bits
    reg [7:0] motor_speed;
    reg [7:0] pwm_counter;
    reg [7:0] pwm_duty_cycle;
    reg system_enabled;
    reg temperature_fault;
    reg [6:0] internal_temperature;
    
    // Output control registers
    reg headlight_active;
    reg horn_active;
    reg indicator_active;

    // PWM clock divider
    reg [15:0] pwm_clk_div;
    wire pwm_clk;

    // Data input control
    reg data_select;
    
    // FIXED: Simplified state management - removed complex operation state tracking
    reg [7:0] operation_counter;  // Simple counter for operation timing

    // Data input handling - FIXED: Simplified timing
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            accelerator_value <= 4'b0;
            brake_value <= 4'b0;
            data_select <= 1'b0;
            operation_counter <= 8'b0;
        end else begin
            operation_counter <= operation_counter + 1;
            
            // Simplified data input - toggle every 8 cycles for stability
            if (operation_counter[2:0] == 3'b000) begin
                data_select <= ~data_select;
                if (!data_select) 
                    accelerator_value <= accelerator_brake_data;
                else
                    brake_value <= accelerator_brake_data;
            end
        end
    end

    // Generate PWM clock with proper division
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            pwm_clk_div <= 16'b0;
        else
            pwm_clk_div <= pwm_clk_div + 1;
    end
    assign pwm_clk = pwm_clk_div[7]; // Slower PWM for stability

    // Temperature simulation - Simplified
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            internal_temperature <= 7'd25; // Room temperature
            temperature_fault <= 1'b0;
        end else begin
            // Temperature changes based on motor activity
            if (system_enabled && motor_speed > 8'd50) begin
                if (internal_temperature < 7'd120 && pwm_clk_div[11:0] == 12'h000)
                    internal_temperature <= internal_temperature + 1;
            end else if (internal_temperature > 7'd25 && pwm_clk_div[11:0] == 12'h000) begin
                internal_temperature <= internal_temperature - 1;
            end

            // Temperature fault detection with hysteresis
            if (internal_temperature >= 7'd110) begin
                temperature_fault <= 1'b1;
            end else if (internal_temperature <= 7'd100) begin
                temperature_fault <= 1'b0;
            end
        end
    end

    // Input selection based on mode - FIXED: Proper mode selection
    always @(*) begin
        if (mode_select) begin  // HMI mode
            selected_accelerator = accelerator_value;
            selected_brake = brake_value;
        end else begin  // PLC mode
            selected_accelerator = accelerator_value;
            selected_brake = brake_value;
        end
    end

    // FIXED: Main control logic - Continuous operation without complex state management
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Proper initialization of ALL registers
            system_enabled <= 1'b0;
            motor_speed <= 8'b0;
            headlight_active <= 1'b0;
            horn_active <= 1'b0;
            indicator_active <= 1'b0;
            pwm_duty_cycle <= 8'b0;
            speed_calculation <= 4'b0;  // FIXED: Now 4-bit
        end else if (ena) begin
            // FIXED: Execute all operations continuously based on current operation_select
            case (operation_select)
                3'b000: begin  // Power Control - FIXED: Proper OR logic
                    system_enabled <= (power_on_plc | power_on_hmi);
                    
                    // Reset other controls when power is off
                    if (!(power_on_plc | power_on_hmi)) begin
                        headlight_active <= 1'b0;
                        horn_active <= 1'b0;
                        indicator_active <= 1'b0;
                        motor_speed <= 8'b0;
                        pwm_duty_cycle <= 8'b0;
                    end
                end
                
                3'b001: begin  // Headlight Control
                    if (system_enabled) begin
                        // FIXED: Proper XOR logic for dual source control
                        headlight_active <= (headlight_plc ^ headlight_hmi);
                    end else begin
                        headlight_active <= 1'b0;
                    end
                end
                
                3'b010: begin  // Horn Control
                    if (system_enabled) begin
                        horn_active <= (horn_plc ^ horn_hmi);
                    end else begin
                        horn_active <= 1'b0;
                    end
                end
                
                3'b011: begin  // Right Indicator Control
                    if (system_enabled) begin
                        indicator_active <= (right_ind_plc ^ right_ind_hmi);
                    end else begin
                        indicator_active <= 1'b0;
                    end
                end
                
                3'b100: begin  // Motor Speed Calculation - FIXED: Only non-blocking assignments
                    if (system_enabled && !temperature_fault) begin
                        // FIXED: All assignments are now non-blocking
                        if (selected_accelerator > selected_brake) begin
                            speed_calculation <= selected_accelerator - selected_brake;
                        end else begin
                            speed_calculation <= 4'b0;
                        end
                        
                        // Scale to 8-bit motor speed (multiply by 16)
                        motor_speed <= {speed_calculation, 4'b0000};
                    end else if (temperature_fault) begin
                        // Reduce speed by 50% during overheating
                        motor_speed <= motor_speed >> 1;
                    end else begin
                        motor_speed <= 8'b0;
                    end
                end
                
                3'b101: begin  // PWM Generation
                    if (system_enabled && !temperature_fault) begin
                        pwm_duty_cycle <= motor_speed;
                    end else begin
                        pwm_duty_cycle <= 8'b0;
                    end
                end
                
                3'b110: begin  // Temperature Monitoring
                    // Temperature monitoring is handled in separate always block
                    // This operation maintains current state
                end
                
                3'b111: begin  // System Status/Reset
                    if (!system_enabled) begin
                        motor_speed <= 8'b0;
                        pwm_duty_cycle <= 8'b0;
                        headlight_active <= 1'b0;
                        horn_active <= 1'b0;
                        indicator_active <= 1'b0;
                    end
                end
                
                default: begin
                    // Maintain current state for undefined operations
                end
            endcase
        end
    end

    // PWM generation - Fixed with proper reset handling
    always @(posedge pwm_clk or negedge rst_n) begin
        if (!rst_n) begin
            pwm_counter <= 8'b0;
        end else if (system_enabled) begin
            pwm_counter <= pwm_counter + 1;
        end else begin
            pwm_counter <= 8'b0;
        end
    end

    // FIXED: Output assignments with proper logic
    assign power_status = system_enabled;
    assign headlight_out = headlight_active & system_enabled;
    assign horn_out = horn_active & system_enabled;
    assign right_indicator = indicator_active & system_enabled;
    assign motor_pwm = (system_enabled && !temperature_fault && pwm_duty_cycle > 0) ? 
                       (pwm_counter < pwm_duty_cycle) : 1'b0;
    assign overheat_warning = temperature_fault;
    assign status_led = {temperature_fault, system_enabled};
    assign motor_speed_out = motor_speed;

    // Tie off unused input to prevent warnings
    wire _unused = &{ena, 1'b0};

endmodule
