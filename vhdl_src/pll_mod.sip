set_global_assignment -entity "pll_mod" -library "lib_pll_mod" -name IP_TOOL_NAME "altera_pll"
set_global_assignment -entity "pll_mod" -library "lib_pll_mod" -name IP_TOOL_VERSION "13.0sp1"
set_global_assignment -entity "pll_mod" -library "lib_pll_mod" -name IP_TOOL_ENV "mwpim"
set_global_assignment -library "lib_pll_mod" -name SPD_FILE [file join $::quartus(sip_path) "pll_mod.spd"]

set_global_assignment -library "lib_pll_mod" -name MISC_FILE [file join $::quartus(sip_path) "pll_mod_sim/pll_mod.vho"]
