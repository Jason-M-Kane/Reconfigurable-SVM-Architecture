set_time_format -unit ns -decimal_places 3

#main clocks
create_clock -period 20 -name {OSC_50_BANK2} {OSC_50_BANK2}
create_clock -period 20 -name {OSC_50_BANK3} {OSC_50_BANK3}
create_clock -period 20 -name {OSC_50_BANK4} {OSC_50_BANK4}
create_clock -period 20 -name {OSC_50_BANK5} {OSC_50_BANK5}
create_clock -period 20 -name {OSC_50_BANK6} {OSC_50_BANK6}
create_clock -period 20 -name {OSC_50_BANK7} {OSC_50_BANK7}
create_clock -period 10 [get_ports GPIO0[11]]

derive_pll_clocks
derive_clock_uncertainty

#all clock pins should be independent
set_clock_groups -asynchronous \
   -group {altera_reserved_tck} \
   -group {OSC_50_BANK2} \
   -group {OSC_50_BANK3} \
   -group {OSC_50_BANK4} \
   -group {OSC_50_BANK5} \
   -group {OSC_50_BANK6} \
   -group {OSC_50_BANK7} \
   -group {GPIO0[11]} \
   -group { \
      mainpll*clk[0] \
      mainpll*clk[1] \
   } \
   -group pcspll*clk[0]}

set_false_path -from [get_ports altera_reserved_*]
set_false_path -to [get_ports altera_reserved_*]

#UART I/O doesn't matter
set_false_path -to [get_ports UART_*]
set_false_path -from [get_ports UART_*]

#these I/O pins don't matter
set_false_path -from [get_ports BUTTON*]
set_false_path -from [get_ports CPU_RESET_n*]
set_false_path -to [get_ports LED*]

#set_false_path -from [get_registers rst]

#pprdma stuff has different timing
#create_generated_clock [get_ports GPIO0[29]] \
#   -name PPRDMA_O_CLK \
#   -source [get_pins mainpll*clk[0]]
#set_output_delay  -max -clock [get_clocks PPRDMA_O_CLK]   5 -to [get_ports GPIO0*]
#set_output_delay  -min -clock [get_clocks PPRDMA_O_CLK]  -3 -to [get_ports GPIO0*]
#set_input_delay   -max -clock [get_clocks GPIO0[11]]      5 -from [get_ports GPIO0*]
#set_input_delay   -min -clock [get_clocks GPIO0[11]]     -3 -from [get_ports GPIO0*]

#clock in min/max
set_min_delay -from [get_ports GPIO0[11]] -to [get_clocks *] 0
set_max_delay -from [get_ports GPIO0[11]] -to [get_clocks *] 7

#input regs min/max
set_min_delay -from [get_ports GPIO0[*]] -1
set_max_delay -from [get_ports GPIO0[*]] 7

#output regs min/max
set_min_delay -to [get_ports GPIO0[*]] 0
set_max_delay -to [get_ports GPIO0[*]] 7

#clock out min/max
set_min_delay -to [get_ports GPIO0[29]] 0
set_max_delay -to [get_ports GPIO0[29]] 7

#backpressure is considered asynchronous
set_false_path -from [get_ports GPIO0[11]] -to [get_ports GPIO0[28]]

set_false_path -from [get_ports ETH_MD*]
set_false_path -to [get_ports ETH_MD*]

set_min_delay -to [get_ports FSM_*] 0
set_max_delay -to [get_ports FSM_*] 10
set_min_delay -from [get_ports FSM_*] -1
set_max_delay -from [get_ports FSM_*] 10
set_min_delay -to [get_ports SSRAM*] 0
set_max_delay -to [get_ports SSRAM*] 10
