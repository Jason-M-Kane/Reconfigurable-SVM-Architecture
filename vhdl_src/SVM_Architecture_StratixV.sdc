set_time_format -unit ns -decimal_places 3

#main clocks
create_clock -period 20 -name {clkin_50} {clkin_50}

derive_pll_clocks
derive_clock_uncertainty

#all clock pins should be independent
set_clock_groups -asynchronous \
   -group {altera_reserved_tck} \
   -group {clkin_50} \
   -group { \
      *general[0].gpll*|divclk
   }

#set_false_path -from [get_ports altera_reserved_*]
#set_false_path -to [get_ports altera_reserved_*]

#these I/O pins don't matter
set_false_path -from [get_ports cpu_resetn*]
set_false_path -to [get_ports hsma_d1_uart_rx*]
set_false_path -from [get_ports hsma_d3_uart_tx*]


