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
    reg [4:0] speed_calculation;
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
    reg [7:0] pwm_clk_div;
    wire pwm_clk;

    // Data input control (simplified for pin constraints)
    reg data_select; // 0: accelerator, 1: brake
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            accelerator_value <= 4'b0;
            brake_value <= 4'b0;
            data_select <= 1'b0;
        end else begin
            // Toggle between accelerator and brake data input
            data_select <= ~data_select;
            if (!data_select) 
                accelerator_value <= accelerator_brake_data;
            else
                brake_value <= accelerator_brake_data;
        end
    end

    // Generate PWM clock
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            pwm_clk_div <= 8'b0;
        else
            pwm_clk_div <= pwm_clk_div + 1;
    end
    assign pwm_clk = pwm_clk_div[4]; // Faster PWM for demo

    // Simple temperature simulation (increases with motor activity)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            internal_temperature <= 7'd25; // Room temperature
            temperature_fault <= 1'b0;
        end else begin
            if (system_enabled && motor_speed > 8'd50) begin
                // Temperature rises slowly with motor activity
                if (internal_temperature < 7'd120 && pwm_clk_div[15:0] == 16'h0000)
                    internal_temperature <= internal_temperature + 1;
            end else if (internal_temperature > 7'd25 && pwm_clk_div[15:0] == 16'h0000) begin
                // Temperature cools down slowly
                internal_temperature <= internal_temperature - 1;
            end

            // Temperature fault detection - Fixed threshold
            if (internal_temperature >= 7'd110) begin
                temperature_fault <= 1'b1;
            end else if (internal_temperature <= 7'd105) begin // 5°C hysteresis
                temperature_fault <= 1'b0;
            end
        end
    end

    // Input selection based on mode
    always @(*) begin
        if (mode_select) begin  // HMI mode
            selected_accelerator = accelerator_value; // Simplified - same data
            selected_brake = brake_value;
        end else begin  // PLC mode
            selected_accelerator = accelerator_value;
            selected_brake = brake_value;
        end
    end

    // Main control logic using case statement
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            system_enabled <= 1'b0;
            motor_speed <= 8'b0;
            headlight_active <= 1'b0;
            horn_active <= 1'b0;
            indicator_active <= 1'b0;
        end else if (ena) begin
            case (operation_select)
                3'b000: begin  // Power Control
                    system_enabled <= (power_on_plc ^ power_on_hmi); // XOR logic
                    // Reset other controls when setting power
                    if (!system_enabled) begin
                        headlight_active <= 1'b0;
                        horn_active <= 1'b0;
                        indicator_active <= 1'b0;
                        motor_speed <= 8'b0;
                    end
                end
                
                3'b001: begin  // Headlight Control
                    if (system_enabled) begin
                        headlight_active <= (headlight_plc ^ headlight_hmi); // XOR logic
                    end else begin
                        headlight_active <= 1'b0;
                    end
                end
                
                3'b010: begin  // Horn Control
                    if (system_enabled) begin
                        horn_active <= (horn_plc ^ horn_hmi); // XOR logic
                    end else begin
                        horn_active <= 1'b0;
                    end
                end
                
                3'b011: begin  // Right Indicator Control
                    if (system_enabled) begin
                        indicator_active <= (right_ind_plc ^ right_ind_hmi); // XOR logic
                    end else begin
                        indicator_active <= 1'b0;
                    end
                end
                
                3'b100: begin  // Motor Speed Calculation
                    if (system_enabled && !temperature_fault) begin
                        // Calculate speed: accelerator - brake
                        if (selected_accelerator > selected_brake) begin
                            speed_calculation = selected_accelerator - selected_brake;
                        end else begin
                            speed_calculation = 5'b0;
                        end
                        
                        // Scale to 8-bit motor speed
                        motor_speed <= {speed_calculation[3:0], 4'b0000};
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
                    // Temperature monitoring handled in separate always block
                    // This case can be used to read temperature status
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
                    // Default case - maintain current state
                end
            endcase
        end
    end

    // PWM generation
    always @(posedge pwm_clk or negedge rst_n) begin
        if (!rst_n) begin
            pwm_counter <= 8'b0;
        end else begin
            pwm_counter <= pwm_counter + 1;
        end
    end

    // Output assignments
    assign power_status = system_enabled;
    assign headlight_out = headlight_active;
    assign horn_out = horn_active;
    assign right_indicator = indicator_active;
    assign motor_pwm = (system_enabled && !temperature_fault) ? 
                       (pwm_counter < pwm_duty_cycle) : 1'b0;
    assign overheat_warning = temperature_fault;
    assign status_led = {system_enabled, temperature_fault};
    assign motor_speed_out = motor_speed;

    // List all unused inputs to prevent warnings
    wire _unused = &{ena, 1'b0};

endmodule
