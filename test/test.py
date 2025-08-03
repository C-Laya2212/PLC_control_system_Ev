# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

@cocotb.test()
async def test_project(dut):
    dut._log.info("Start")
    
    # Set the clock period to 10 us (100 KHz)
    clock = Clock(dut.clk, 10, units="us")
    cocotb.start_soon(clock.start())
    
    # Reset
    dut._log.info("Reset")
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    
    dut._log.info("=== Testing EV Motor Control Module ===")
    
    # Test 1: Power Control (operation_select = 3'b000)
    dut._log.info("Test 1: Power Control")
    dut.ui_in.value = 0b00001000  # power_on_plc=1, power_on_hmi=0, operation_select=000
    await ClockCycles(dut.clk, 5)
    
    # Check power status (uo_out[0])
    power_status = dut.uo_out.value & 0x01
    dut._log.info(f"Power Status: {power_status}")
    assert power_status == 1, "Power should be ON (PLC XOR HMI = 1 XOR 0 = 1)"
    
    # Test 2: Headlight Control (operation_select = 3'b001)
    dut._log.info("Test 2: Headlight Control")
    dut.ui_in.value = 0b01000001  # headlight_plc=1, headlight_hmi=0, operation_select=001
    await ClockCycles(dut.clk, 5)
    
    # Check headlight status (uo_out[1])
    headlight_status = (dut.uo_out.value >> 1) & 0x01
    dut._log.info(f"Headlight Status: {headlight_status}")
    assert headlight_status == 1, "Headlight should be ON"
    
    # Test 3: Horn Control (operation_select = 3'b010)
    dut._log.info("Test 3: Horn Control")
    dut.ui_in.value = 0b00000010  # operation_select=010
    dut.uio_in.value = 0b00000001  # horn_plc=1, horn_hmi=0
    await ClockCycles(dut.clk, 5)
    
    # Check horn status (uo_out[2])
    horn_status = (dut.uo_out.value >> 2) & 0x01
    dut._log.info(f"Horn Status: {horn_status}")
    assert horn_status == 1, "Horn should be ON"
    
    # Test 4: Right Indicator Control (operation_select = 3'b011)
    dut._log.info("Test 4: Right Indicator Control")
    dut.ui_in.value = 0b00000011  # operation_select=011
    dut.uio_in.value = 0b00000100  # right_ind_plc=1, right_ind_hmi=0
    await ClockCycles(dut.clk, 5)
    
    # Check indicator status (uo_out[3])
    indicator_status = (dut.uo_out.value >> 3) & 0x01
    dut._log.info(f"Right Indicator Status: {indicator_status}")
    assert indicator_status == 1, "Right Indicator should be ON"
    
    # Test 5: Motor Speed Calculation (operation_select = 3'b100)
    dut._log.info("Test 5: Motor Speed Calculation")
    
    # First set accelerator data
    dut.ui_in.value = 0b00000100  # operation_select=100
    dut.uio_in.value = 0b11000000  # accelerator_brake_data = 12 (1100)
    await ClockCycles(dut.clk, 2)  # Wait for data_select toggle
    
    # Then set brake data
    dut.uio_in.value = 0b01000000  # accelerator_brake_data = 4 (0100)
    await ClockCycles(dut.clk, 5)
    
    # Check motor speed output (uio_out)
    motor_speed = dut.uio_out.value
    dut._log.info(f"Motor Speed: {motor_speed}")
    # Expected: (12-4) << 4 = 8 << 4 = 128
    expected_speed = 128
    assert motor_speed == expected_speed, f"Motor speed should be {expected_speed}, got {motor_speed}"
    
    # Test 6: PWM Generation (operation_select = 3'b101)
    dut._log.info("Test 6: PWM Generation")
    dut.ui_in.value = 0b00000101  # operation_select=101
    await ClockCycles(dut.clk, 10)
    
    # Monitor PWM signal for several cycles
    pwm_values = []
    for i in range(20):
        pwm_status = (dut.uo_out.value >> 4) & 0x01
        pwm_values.append(pwm_status)
        await ClockCycles(dut.clk, 1)
    
    # PWM should have both high and low values
    pwm_high_count = sum(pwm_values)
    dut._log.info(f"PWM High Count: {pwm_high_count}/20")
    assert 0 < pwm_high_count < 20, "PWM should toggle between high and low"
    
    # Test 7: Temperature Monitoring
    dut._log.info("Test 7: Temperature Monitoring and Fault Detection")
    
    # Run motor at high speed for extended time to trigger temperature rise
    dut.ui_in.value = 0b00000100  # operation_select=100 (motor speed)
    dut.uio_in.value = 0b11110000  # High accelerator value (15)
    await ClockCycles(dut.clk, 10)
    dut.uio_in.value = 0b00000000  # Low brake value (0)
    await ClockCycles(dut.clk, 100)  # Let motor run to build up heat
    
    # Check for overheat warning (uo_out[5])
    overheat_status = (dut.uo_out.value >> 5) & 0x01
    dut._log.info(f"Overheat Warning: {overheat_status}")
    
    # Test 8: System Status LEDs
    dut._log.info("Test 8: System Status LEDs")
    
    # Check status LED bits (uo_out[7:6])
    status_leds = (dut.uo_out.value >> 6) & 0x03
    system_enabled_led = status_leds & 0x01
    temp_fault_led = (status_leds >> 1) & 0x01
    
    dut._log.info(f"System Enabled LED: {system_enabled_led}")
    dut._log.info(f"Temperature Fault LED: {temp_fault_led}")
    
    # Test 9: Mode Selection (PLC vs HMI)
    dut._log.info("Test 9: Mode Selection")
    
    # Test HMI mode
    dut.ui_in.value = 0b00100000  # mode_select=1 (HMI mode), operation_select=000
    dut.ui_in.value |= 0b00010000  # power_on_hmi=1
    await ClockCycles(dut.clk, 5)
    
    power_status_hmi = dut.uo_out.value & 0x01
    dut._log.info(f"Power Status in HMI mode: {power_status_hmi}")
    
    # Test 10: System Reset (operation_select = 3'b111)
    dut._log.info("Test 10: System Reset")
    dut.ui_in.value = 0b00000111  # operation_select=111
    await ClockCycles(dut.clk, 5)
    
    # All outputs should be reset when system is disabled
    final_output = dut.uo_out.value
    dut._log.info(f"Final output after reset: {bin(final_output)}")
    
    # Test 11: Edge Cases
    dut._log.info("Test 11: Edge Cases")
    
    # Test brake > accelerator case
    dut.ui_in.value = 0b00000100  # operation_select=100
    dut.uio_in.value = 0b01000000  # Set lower accelerator (4)
    await ClockCycles(dut.clk, 2)
    dut.uio_in.value = 0b11000000  # Set higher brake (12)
    await ClockCycles(dut.clk, 5)
    
    motor_speed_edge = dut.uio_out.value
    dut._log.info(f"Motor Speed (brake > accel): {motor_speed_edge}")
    assert motor_speed_edge == 0, "Motor speed should be 0 when brake > accelerator"
    
    # Test 12: Power Off Behavior
    dut._log.info("Test 12: Power Off Behavior")
    
    # Turn off power
    dut.ui_in.value = 0b00000000  # All controls off, operation_select=000
    await ClockCycles(dut.clk, 5)
    
    # Test that other functions don't work when power is off
    dut.ui_in.value = 0b01000001  # Try to turn on headlight
    await ClockCycles(dut.clk, 5)
    
    headlight_off = (dut.uo_out.value >> 1) & 0x01
    dut._log.info(f"Headlight when power off: {headlight_off}")
    assert headlight_off == 0, "Headlight should be OFF when system power is OFF"
    
    dut._log.info("=== All Tests Completed Successfully ===")
