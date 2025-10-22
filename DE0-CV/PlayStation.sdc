create_clock -name inclk50 -period 50MHz [get_ports CLOCK_50]

#set clk_sdram_device {sdram_pll_100_inst|altera_pll_i|general[2].gpll~PLL_OUTPUT_COUNTER|divclk}
#set clk_sdram_ctrl   {sdram_pll_100_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk}

create_generated_clock -name clk_core -source [get_ports {CLOCK_50}] [get_pins {sdram_pll_100_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}]
create_generated_clock -name clk_sdram_ctrl -source [get_ports {CLOCK_50}] -multiply_by 2 [get_pins {sdram_pll_100_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk}]
create_generated_clock -name clk_sdram_device -source [get_ports {CLOCK_50}] -multiply_by 2 -phase -3.000 [get_pins {sdram_pll_100_inst|altera_pll_i|general[2].gpll~PLL_OUTPUT_COUNTER|divclk}]

derive_pll_clocks
derive_clock_uncertainty

set_false_path -from inclk50 -to clk_sdram_device
set_false_path -from inclk50 -to clk_sdram_ctrl
set_false_path -from clk_sdram_ctrl -to inclk50
set_false_path -from clk_sdram_device
#set_false_path -from clk_sdram_ctrl -to clk_core
#set_false_path -from clk_core -to clk_sdram_ctrl

set PERIOD 20
set tSetUp 13
set tHold 3
set_input_delay -clock inclk50 -max [expr $PERIOD - $tSetUp] [all_inputs]
set_input_delay -clock inclk50 -min [expr $tHold] [all_inputs]
set tCOMAX 18
set tCOMIN 1
set_output_delay -clock inclk50 -max [expr $PERIOD - $tCOMAX] [all_outputs]
set_output_delay -clock inclk50 -min [expr -$tCOMIN] [all_outputs]

set_output_delay -clock clk_sdram_device -max 1.5ns [get_ports {DRAM_ADDR* DRAM_BA* DRAM_CKE DRAM_RAS_N DRAM_CAS_N DRAM_CS_N DRAM_WE_N DRAM_LDQM DRAM_UDQM}]
set_output_delay -clock clk_sdram_device -min -4.8ns [get_ports {DRAM_ADDR* DRAM_BA* DRAM_CKE DRAM_RAS_N DRAM_CAS_N DRAM_CS_N DRAM_WE_N DRAM_LDQM DRAM_UDQM}]
set_input_delay -clock clk_sdram_device -max 5.4ns -add_delay [get_ports {DRAM_DQ[*]}]
set_input_delay -clock clk_sdram_device -min 2.7ns -add_delay [get_ports {DRAM_DQ[*]}]
set_output_delay -clock clk_sdram_device -max 1.5ns -add_delay [get_ports {DRAM_DQ[*]}]
set_output_delay -clock clk_sdram_device -min -4.8ns -add_delay [get_ports {DRAM_DQ[*]}]
