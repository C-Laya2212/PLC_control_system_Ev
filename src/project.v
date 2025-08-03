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
    
    // SIMPLIFIED: Use uio_in directly for accel/brake - no complex timing
    wire [3:0] accelerator_input = uio_in[7:4]; // Direct accelerator input
    wire [3:0] brake_input = uio_in[3:0];       // Direct brake input (reusing lower bits)

    // Set uio_oe to control bidirectional pins (1=output, 0=input)
    assign uio_oe = 8'b11110000;  // uio[7:4] as outputs, uio[3:0] as inputs

    // Internal registers and wires
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
    reg motor_active;
    reg pwm_active;

    // PWM timing control
    reg [15:0] pwm_clk_div;
    wire pwm_clk;

    // Generate PWM clock
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pwm_clk_div <= 16'b0;
        end else begin
            pwm_clk_div <= pwm_clk_div + 1;
        end
    end
    assign pwm_clk = pwm_clk_div[4]; // Fast PWM

    // =============================================================================
    // TEMPERATURE MONITORING
    // =============================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            internal_temperature <= 7'd25; // Room temperature
            temperature_fault <= 1'b0;
        end else begin
            // Temperature rises with motor activity
            if (system_enabled && motor_speed > 8'd50) begin
                if (internal_temperature < 7'd100 && pwm_clk_div[9:0] == 10'h000)
                    internal_temperature <= internal_temperature + 1;
            end else if (internal_temperature > 7'd25 && pwm_clk_div[9:0] == 10'h000) begin
                internal_temperature <= internal_temperature - 1;
            end

            // Temperature fault detection
            if (internal_temperature >= 7'd85) begin
                temperature_fault <= 1'b1;
            end else if (internal_temperature <= 7'd75) begin
                temperature_fault <= 1'b0;
            end
        end
    end

    // =============================================================================
    // MAIN CONTROL LOGIC - DIRECT MOTOR SPEED CALCULATION
    // =============================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Initialize ALL registers
            system_enabled <= 1'b0;
            motor_speed <= 8'b0;
            headlight_active <= 1'b0;
            horn_active <= 1'b0;
            indicator_active <= 1'b0;
            motor_active <= 1'b0;
            pwm_active <= 1'b0;
            pwm_duty_cycle <= 8'b0;
        end else if (ena) begin
            
            // Power control is always evaluated
            system_enabled <= (power_on_plc | power_on_hmi);
            
            // Reset all outputs when power is off
            if (!(power_on_plc | power_on_hmi)) begin
                headlight_active <= 1'b0;
                horn_active <= 1'b0;
                indicator_active <= 1'b0;
                motor_active <= 1'b0;
                pwm_active <= 1'b0;
                motor_speed <= 8'b0;
                pwm_duty_cycle <= 8'b0;
            end else begin
                // Execute operations when system is powered
                case (operation_select)
                    // =================================================================
                    // CASE 0: POWER CONTROL
                    // =================================================================
                    3'b000: begin
                        // Power control handled above
                    end
                    
                    // =================================================================
                    // CASE 1: HEADLIGHT CONTROL
                    // =================================================================
                    3'b001: begin
                        headlight_active <= (headlight_plc ^ headlight_hmi);
                    end
                    
                    // =================================================================
                    // CASE 2: HORN CONTROL
                    // =================================================================
                    3'b010: begin
                        horn_active <= (horn_plc ^ horn_hmi);
                    end
                    
                    // =================================================================
                    // CASE 3: RIGHT INDICATOR CONTROL
                    // =================================================================
                    3'b011: begin
                        indicator_active <= (right_ind_plc ^ right_ind_hmi);
                    end
                    
                    // =================================================================
                    // CASE 4: MOTOR SPEED - DIRECT CALCULATION (NO TIMING ISSUES)
                    // =================================================================
                    3'b100: begin
                        motor_active <= 1'b1;
                        if (!temperature_fault) begin
                            // DIRECT calculation using current input values
                            if (accelerator_input > brake_input) begin
                                motor_speed <= (accelerator_input - brake_input) << 4; // Scale by 16
                            end else begin
                                motor_speed <= 8'b0;
                            end
                        end else begin
                            motor_speed <= motor_speed >> 1; // Reduce during overheat
                        end
                    end
                    
                    // =================================================================
                    // CASE 5: PWM GENERATION
                    // =================================================================
                    3'b101: begin
                        pwm_active <= 1'b1;
                        if (!temperature_fault) begin
                            pwm_duty_cycle <= motor_speed;
                        end else begin
                            pwm_duty_cycle <= motor_speed >> 1;
                        end
                    end
                    
                    // =================================================================
                    // CASE 6: TEMPERATURE MONITORING
                    // =================================================================
                    3'b110: begin
                        // Temperature monitoring handled separately
                    end
                    
                    // =================================================================
                    // CASE 7: SYSTEM RESET
                    // =================================================================
                    3'b111: begin
                        motor_speed <= 8'b0;
                        pwm_duty_cycle <= 8'b0;
                        headlight_active <= 1'b0;
                        horn_active <= 1'b0;
                        indicator_active <= 1'b0;
                        motor_active <= 1'b0;
                        pwm_active <= 1'b0;
                    end
                    
                    default: begin
                        // Maintain current state
                    end
                endcase
            end
        end
    end

    // =============================================================================
    // PWM GENERATION HARDWARE
    // =============================================================================
    always @(posedge pwm_clk or negedge rst_n) begin
        if (!rst_n) begin
            pwm_counter <= 8'b0;
        end else if (system_enabled) begin
            pwm_counter <= pwm_counter + 1;
        else begin
            pwm_counter <= 8'b0;
        end
    end

    // =============================================================================
    // OUTPUT ASSIGNMENTS
    // =============================================================================
    wire power_status = system_enabled;
    wire headlight_out = headlight_active & system_enabled;
    wire horn_out = horn_active & system_enabled;
    wire right_indicator = indicator_active & system_enabled;
    
    // PWM output - FIXED to work properly
    wire motor_pwm = (system_enabled && pwm_duty_cycle > 8'b0) ? 
                     (pwm_counter < pwm_duty_cycle) : 1'b0;
                     
    wire overheat_warning = temperature_fault;
    wire [1:0] status_led = {temperature_fault, system_enabled};

    // Final output assignments
    assign uo_out = {status_led[1:0], overheat_warning, motor_pwm, 
                     right_indicator, horn_out, headlight_out, power_status};
    
    // Output motor speed for debugging
    assign uio_out = motor_speed;

    // Tie off unused signals
    wire _unused = &{ena, mode_select, motor_active, pwm_active, 1'b0};

endmodule
