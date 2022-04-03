create_clock -name inclk50 -period 50MHz [get_ports {CLOCK2_50}]

set clk50            {psx_pll_inst|altpll_component|auto_generated|pll1|clk[0]}
set clk_sdram_device {psx_pll_inst|altpll_component|auto_generated|pll1|clk[1]}
set clk_sdram_ctrl   {psx_pll_inst|altpll_component|auto_generated|pll1|clk[2]}
set clk_audio        {psx_pll_inst|altpll_component|auto_generated|pll1|clk[3]}
create_clock -name clk_audcnt -period 18.432MHz [get_registers {AUDIO_ctrl:AU|oAUD_BCK}]
create_clock -name clk_i2c -period 20KHz [get_registers {I2C_AV_Config:DACConfU|mI2C_CTRL_CLK}]

derive_pll_clocks
derive_clock_uncertainty

set PERIOD 20
set tSetUp 13
set tHold 3
set_input_delay -clock $clk50 -max [expr $PERIOD - $tSetUp] [all_inputs]
set_input_delay -clock $clk50 -min [expr $tHold] [all_inputs]
set tCOMAX 18
set tCOMIN 1
set_output_delay -clock $clk50 -max [expr $PERIOD - $tCOMAX] [all_outputs]
set_output_delay -clock $clk50 -min [expr -$tCOMIN] [all_outputs]

set_input_delay -clock $clk_sdram_device -max 6.4ns -add_delay [get_ports {DRAM_DQ[*]}]
set_input_delay -clock $clk_sdram_device -min 3.7ns -add_delay [get_ports {DRAM_DQ[*]}]
set_output_delay -clock $clk_sdram_device -max 1.6ns -add_delay [get_ports {DRAM_DQ* DRAM_ADDR* DRAM_BA* DRAM_CKE DRAM_CLK DRAM_RAS_N DRAM_CAS_N DRAM_CS_N DRAM_WE_N}]
set_output_delay -clock $clk_sdram_device -min -0.9ns -add_delay [get_ports {DRAM_DQ* DRAM_ADDR* DRAM_BA* DRAM_CKE DRAM_CLK DRAM_RAS_N DRAM_CAS_N DRAM_CS_N DRAM_WE_N}]

set_false_path -from $clk50 -to $clk_audio
set_false_path -from $clk_audio -to $clk50
set_false_path -from $clk_sdram_device
set_false_path -from $clk50 -to $clk_sdram_ctrl
set_false_path -from $clk_sdram_ctrl -to $clk_sdram_device
set_false_path -from clk_audcnt -to $clk50
set_false_path -from $clk50 -to clk_audcnt
set_false_path -from $clk50 -to clk_i2c
set_false_path -from clk_i2c -to $clk50
set_false_path -from clk_audcnt -to $clk_audio
set_false_path -from $clk_audio -to clk_audcnt

set_false_path -from [get_ports {KEY[*]}]
set_false_path -from [get_ports {SW[*]}]
set_false_path -to [get_ports {LEDG[*]}]
set_false_path -to [get_ports {LEDR[*]}]
set_false_path -to [get_ports {HEX*}]
set_false_path -to [get_ports {VGA_*}]
