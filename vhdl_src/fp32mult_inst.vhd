fp32mult_inst : fp32mult PORT MAP (
		aclr	 => aclr_sig,
		clk_en	 => clk_en_sig,
		clock	 => clock_sig,
		dataa	 => dataa_sig,
		datab	 => datab_sig,
		result	 => result_sig
	);
