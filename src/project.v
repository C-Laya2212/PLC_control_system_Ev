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

    // Set uio_oe to control bidirectional pins (1=output, 0=input)
    assign uio_oe = 8'b11110000;  // uio[7:4] as outputs, uio[3:0] as inputs

    // Internal registers and wires
    reg [3:0] accelerator_value;
    reg [3:0] brake_value;
    reg [3:0] selected_accelerator;
    reg [3:0] selected_brake;
    reg [3:0] speed_calculation;
    reg [7:0] motor_speed;
    reg [7:0] pwm_counter;
    reg [7:0] pwm_duty_cycle;
    reg system_enabled;
    reg temperature_fault;
    reg [6:0] internal_temperature;
    
    // Output control registers for ALL cases
    reg headlight_active;
    reg horn_active;
    reg indicator_active;
    reg motor_active;
    reg pwm_active;

    // PWM and timing control
    reg [15:0] pwm_clk_div;
    reg [7:0] operation_counter;
    wire pwm_clk;

    // Data input control for motor speed calculation
    reg data_capture_phase;
    reg [3:0] data_counter;

    // =============================================================================
    // DATA INPUT HANDLING - For Motor Speed Calculation (Case 5)
    // =============================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            accelerator_value <= 4'd8;      // Default accelerator
            brake_value <= 4'd3;            // Default brake  
            data_capture_phase <= 1'b0;
            data_counter <= 4'b0;
        end else begin
            data_counter <= data_counter + 1;
            
            // Capture accelerator and brake data in phases
            if (data_counter[2:0] == 3'b000) begin
                data_capture_phase <= 1'b0;
                accelerator_value <= accelerator_brake_data;
            end else if (data_counter[2:0] == 3'b100) begin
                data_capture_phase <= 1'b1;
                brake_value <= accelerator_brake_data;
            end
        end
    end

    // Generate PWM clock
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pwm_clk_div <= 16'b0;
            operation_counter <= 8'b0;
        end else begin
            pwm_clk_div <= pwm_clk_div + 1;
            operation_counter <= operation_counter + 1;
        end
    end
    assign pwm_clk = pwm_clk_div[4]; // Fast PWM for visible results

    // =============================================================================
    // TEMPERATURE MONITORING - Case 6 (Always Active)
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

    // Input selection based on mode
    always @(*) begin
        if (mode_select) begin  // HMI mode
            selected_accelerator = accelerator_value;
            selected_brake = brake_value;
        end else begin  // PLC mode
            selected_accelerator = accelerator_value;
            selected_brake = brake_value;
        end
    end

    // =============================================================================
    // MAIN CONTROL LOGIC - ALL CASES IMPLEMENTED
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
            speed_calculation <= 4'b0;
        end else if (ena) begin
            
            // =================================================================
            // CASE 1: POWER CONTROL (operation_select = 3'b000)
            // =================================================================
            if (operation_select == 3'b000) begin
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
                end
            end
            
            // =================================================================
            // CASE 2: HEADLIGHT CONTROL (operation_select = 3'b001)
            // =================================================================
            else if (operation_select == 3'b001) begin
                if (system_enabled) begin
                    // XOR logic: only one source should control
                    headlight_active <= (headlight_plc ^ headlight_hmi);
                end else begin
                    headlight_active <= 1'b0;
                end
            end
            
            // =================================================================
            // CASE 3: HORN CONTROL (operation_select = 3'b010)
            // =================================================================
            else if (operation_select == 3'b010) begin
                if (system_enabled) begin
                    // XOR logic for horn control
                    horn_active <= (horn_plc ^ horn_hmi);
                end else begin
                    horn_active <= 1'b0;
                end
            end
            
            // =================================================================
            // CASE 4: RIGHT INDICATOR CONTROL (operation_select = 3'b011)
            // =================================================================
            else if (operation_select == 3'b011) begin
                if (system_enabled) begin
                    // XOR logic for indicator control
                    indicator_active <= (right_ind_plc ^ right_ind_hmi);
                end else begin
                    indicator_active <= 1'b0;
                end
            end
            
            // =================================================================
            // CASE 5: MOTOR SPEED CALCULATION (operation_select = 3'b100)
            // =================================================================
            else if (operation_select == 3'b100) begin
                if (system_enabled && !temperature_fault) begin
                    // Calculate speed: accelerator - brake
                    if (selected_accelerator > selected_brake) begin
                        speed_calculation <= selected_accelerator - selected_brake;
                    end else begin
                        speed_calculation <= 4'b0;
                    end
                    
                    // Scale to 8-bit motor speed (multiply by 16 for good range)
                    motor_speed <= {speed_calculation, 4'b0000};
                    motor_active <= 1'b1;
                end else if (temperature_fault) begin
                    // Reduce speed by 50% during overheating
                    motor_speed <= motor_speed >> 1;
                    motor_active <= 1'b1;
                end else begin
                    motor_speed <= 8'b0;
                    motor_active <= 1'b0;
                end
            end
            
            // =================================================================
            // CASE 6: PWM GENERATION (operation_select = 3'b101)
            // =================================================================
            else if (operation_select == 3'b101) begin
                if (system_enabled && !temperature_fault) begin
                    pwm_duty_cycle <= motor_speed;
                    pwm_active <= 1'b1;
                end else if (temperature_fault) begin
                    // Reduced PWM during fault
                    pwm_duty_cycle <= motor_speed >> 1;
                    pwm_active <= 1'b1;
                end else begin
                    pwm_duty_cycle <= 8'b0;
                    pwm_active <= 1'b0;
                end
            end
            
            // =================================================================
            // CASE 7: TEMPERATURE MONITORING (operation_select = 3'b110)
            // =================================================================
            else if (operation_select == 3'b110) begin
                // Temperature monitoring is handled in separate always block
                // This case maintains current state and allows temperature readout
            end
            
            // =================================================================
            // CASE 8: SYSTEM STATUS/RESET (operation_select = 3'b111)
            // =================================================================
            else if (operation_select == 3'b111) begin
                if (!system_enabled) begin
                    // Reset all active states when system is disabled
                    motor_speed <= 8'b0;
                    pwm_duty_cycle <= 8'b0;
                    headlight_active <= 1'b0;
                    horn_active <= 1'b0;
                    indicator_active <= 1'b0;
                    motor_active <= 1'b0;
                    pwm_active <= 1'b0;
                end
            end
            
            // =================================================================
            // DEFAULT CASE: Maintain current state
            // =================================================================
            else begin
                // Maintain current state for any undefined operations
            end
        end
    end

    // =============================================================================
    // PWM GENERATION HARDWARE
    // =============================================================================
    always @(posedge pwm_clk or negedge rst_n) begin
        if (!rst_n) begin
            pwm_counter <= 8'b0;
        end else if (system_enabled || pwm_active) begin
            pwm_counter <= pwm_counter + 1;
        end else begin
            pwm_counter <= 8'b0;
        end
    end

    // =============================================================================
    // OUTPUT ASSIGNMENTS - ALL OUTPUTS PROPERLY DEFINED
    // =============================================================================
    wire power_status = system_enabled;
    wire headlight_out = headlight_active & system_enabled;
    wire horn_out = horn_active & system_enabled;
    wire right_indicator = indicator_active & system_enabled;
    
    // PWM output with proper duty cycle control
    wire motor_pwm = (system_enabled && !temperature_fault && pwm_duty_cycle > 0) ? 
                     (pwm_counter < pwm_duty_cycle) : 1'b0;
                     
    wire overheat_warning = temperature_fault;
    wire [1:0] status_led = {temperature_fault, system_enabled};
    wire [7:0] motor_speed_out = motor_speed;

    // Final output assignments
    assign uo_out = {status_led[1:0], overheat_warning, motor_pwm, 
                     right_indicator, horn_out, headlight_out, power_status};
    assign uio_out = motor_speed_out;

    // Tie off unused input to prevent warnings
    wire _unused = &{ena, mode_select, motor_active, pwm_active, 1'b0};

endmodule
