current_design qosoc_chip_top
set_units -time ns -resistance kOhm -capacitance pF -voltage V -current uA

create_clock -name clk_i -period 62.5 [get_ports {clk_PAD}]
create_clock -name clk_rtc_i -period 30517.578 [get_ports {clk_rtc_PAD}]

###############################################################################
# Generated (Gated) Clocks — derived from clk_i via sg13g2_lgcp_1 ICG cells
###############################################################################
create_generated_clock -name clk_cpu \
    -source [get_ports {clk_PAD}] \
    -master_clock clk_i \
    -combinational \
    [get_pins {u_qosoc_core.u_cpu_clk_gate.u_lgcp/GCLK}]

create_generated_clock -name clk_gpio \
    -source [get_ports {clk_PAD}] \
    -master_clock clk_i \
    -combinational \
    [get_pins {u_qosoc_core.u_gpio.u_clk_gate.u_lgcp/GCLK}]

create_generated_clock -name clk_i2c \
    -source [get_ports {clk_PAD}] \
    -master_clock clk_i \
    -combinational \
    [get_pins {u_qosoc_core.u_i2c.u_clk_gate.u_lgcp/GCLK}]

create_generated_clock -name cntr_clk \
    -source [get_ports {clk_PAD}] \
    -master_clock clk_i \
    -combinational \
    [get_nets {u_qosoc_core.u_ptc0.u_ptc.cntr_clk}]

create_generated_clock -name hrc_clk \
    -source [get_ports {clk_PAD}] \
    -master_clock clk_i \
    -combinational \
    [get_nets {u_qosoc_core.u_ptc0.u_ptc.hrc_clk}]

create_generated_clock -name lrc_clk \
    -source [get_ports {clk_PAD}] \
    -master_clock clk_i \
    -combinational \
    [get_nets {u_qosoc_core.u_ptc0.u_ptc.lrc_clk}]

###############################################################################
# Clock Uncertainties
###############################################################################
#set_clock_uncertainty -setup 2.5  [get_clocks clk_i]
#set_clock_uncertainty -hold  0.15 [get_clocks clk_i]

foreach gc {clk_cpu clk_gpio clk_i2c cntr_clk hrc_clk lrc_clk} {
    set_clock_uncertainty -setup 2.5  [get_clocks $gc]
    set_clock_uncertainty -hold  0.15 [get_clocks $gc]
}

set_clock_uncertainty -setup 5.0 [get_clocks clk_rtc_i]
set_clock_uncertainty -hold  0.3 [get_clocks clk_rtc_i]

###############################################################################
# Clock Characteristics
###############################################################################
set_clock_transition 1.0 [get_clocks clk_i]
set_clock_latency -source 1.5 [get_clocks clk_i]

set_clock_transition 2.0 [get_clocks clk_rtc_i]
set_clock_latency -source 2.0 [get_clocks clk_rtc_i]

###############################################################################
# Clock Domain Relationships
###############################################################################
set_clock_groups -asynchronous \
    -group [get_clocks {clk_i clk_cpu clk_gpio clk_i2c cntr_clk hrc_clk lrc_clk}] \
    -group [get_clocks {clk_rtc_i}]

###############################################################################
# Clock Gating Checks
###############################################################################
set_clock_gating_check -setup 1.0 [get_clocks clk_i]
set_clock_gating_check -hold  0.3 [get_clocks clk_i]

set_clock_gating_check -setup 2.0 [get_clocks clk_rtc_i]
set_clock_gating_check -hold  0.5 [get_clocks clk_rtc_i]

###############################################################################
# False Paths
###############################################################################
set_false_path -from [get_ports {rst_n_PAD}]

###############################################################################
# SRAM Structural Hold Constraint
###############################################################################
set_multicycle_path -hold 0 \
    -from [get_clocks {clk_cpu clk_i}] \
    -to   [get_pins  {u_qosoc_core.u_sram.u_sram/A_DIN[*] \
                      u_qosoc_core.u_sram.u_sram/A_WEN     \
                      u_qosoc_core.u_sram.u_sram/A_REN     \
                      u_qosoc_core.u_sram.u_sram/A_ADDR[*]}]

set_false_path -hold \
    -from [get_clocks {clk_i clk_cpu clk_gpio clk_i2c}] \
    -to   [get_clocks {clk_rtc_i}]

set_false_path -hold \
    -from [get_clocks {clk_rtc_i}] \
    -to   [get_clocks {clk_i clk_cpu clk_gpio clk_i2c}]

set_input_transition 0.5 [get_ports {clk_PAD}]
set_input_transition 1.0 [get_ports {clk_rtc_PAD}]
set_input_transition 0.5 [get_ports {rst_n_PAD}]
set_input_transition 0.5 [get_ports {uart_rx_PAD}]
set_input_transition 0.5 [get_ports {i2c_scl_PAD}]
set_input_transition 0.5 [get_ports {i2c_sda_PAD}]
set_input_transition 0.5 [get_ports {pwm0_PAD}]

foreach bit {0 1 2 3} {
    set_input_transition 0.5 [get_ports "qspi_dat_PAD\[$bit\]"]
}

###############################################################################
# Input Delays
###############################################################################
foreach bit {0 1 2 3 4 5 6 7} {
    set_input_transition 0.5 [get_ports "gpio_PAD\[$bit\]"]
}

set input_max_dly 15.0
set input_min_dly  4.0

set_input_delay -clock clk_i -max $input_max_dly  [get_ports {uart_rx_PAD}]
set_input_delay -clock clk_i -min $input_min_dly  [get_ports {uart_rx_PAD}]

set_input_delay -clock clk_i -max $input_max_dly  [get_ports {i2c_scl_PAD}]
set_input_delay -clock clk_i -min $input_min_dly  [get_ports {i2c_scl_PAD}]
set_input_delay -clock clk_i -max $input_max_dly  [get_ports {i2c_sda_PAD}]
set_input_delay -clock clk_i -min $input_min_dly  [get_ports {i2c_sda_PAD}]

set_input_delay -clock clk_i -max $input_max_dly  [get_ports {pwm0_PAD}]
set_input_delay -clock clk_i -min $input_min_dly  [get_ports {pwm0_PAD}]

foreach bit {0 1 2 3} {
    set_input_delay -clock clk_i -max $input_max_dly [get_ports "qspi_dat_PAD\[$bit\]"]
    set_input_delay -clock clk_i -min $input_min_dly [get_ports "qspi_dat_PAD\[$bit\]"]
}

foreach bit {0 1 2 3 4 5 6 7} {
    set_input_delay -clock clk_i -max $input_max_dly [get_ports "gpio_PAD\[$bit\]"]
    set_input_delay -clock clk_i -min $input_min_dly [get_ports "gpio_PAD\[$bit\]"]
}

###############################################################################
# Output Load and Delays
###############################################################################
set output_load    2.0
set output_max_dly 10.0
set output_min_dly  2.0

set_load $output_load [all_outputs]

set_output_delay -clock clk_i -max $output_max_dly [get_ports {uart_tx_PAD}]
set_output_delay -clock clk_i -min $output_min_dly [get_ports {uart_tx_PAD}]

set_output_delay -clock clk_i -max $output_max_dly [get_ports {i2c_scl_PAD}]
set_output_delay -clock clk_i -min $output_min_dly [get_ports {i2c_scl_PAD}]
set_output_delay -clock clk_i -max $output_max_dly [get_ports {i2c_sda_PAD}]
set_output_delay -clock clk_i -min $output_min_dly [get_ports {i2c_sda_PAD}]

set_output_delay -clock clk_i -max $output_max_dly [get_ports {pwm0_PAD}]
set_output_delay -clock clk_i -min $output_min_dly [get_ports {pwm0_PAD}]

set_output_delay -clock clk_i -max 8.0 [get_ports {qspi_sck_PAD}]
set_output_delay -clock clk_i -min 2.5 [get_ports {qspi_sck_PAD}]
set_output_delay -clock clk_i -max 8.0 [get_ports {qspi_cs_n_PAD}]
set_output_delay -clock clk_i -min 2.5 [get_ports {qspi_cs_n_PAD}]

foreach bit {0 1 2 3} {
    set_output_delay -clock clk_i -max $output_max_dly [get_ports "qspi_dat_PAD\[$bit\]"]
    set_output_delay -clock clk_i -min $output_min_dly [get_ports "qspi_dat_PAD\[$bit\]"]
}

foreach bit {0 1 2 3 4 5 6 7} {
    set_output_delay -clock clk_i -max $output_max_dly [get_ports "gpio_PAD\[$bit\]"]
    set_output_delay -clock clk_i -min $output_min_dly [get_ports "gpio_PAD\[$bit\]"]
}

set_output_delay -clock clk_i -max 12.0 [get_ports {trap_PAD}]
set_output_delay -clock clk_i -min  1.0 [get_ports {trap_PAD}]

###############################################################################
# Design Rule Constraints
###############################################################################
set_max_transition  1.5 [current_design]
set_max_capacitance 0.5 [current_design]
set_max_fanout       16 [current_design]
