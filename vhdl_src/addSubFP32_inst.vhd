addSubFP32_inst : addSubFP32 PORT MAP (
		aclr	 => aclr_sig,
		add_sub	 => add_sub_sig,
		clk_en	 => clk_en_sig,
		clock	 => clock_sig,
		dataa	 => dataa_sig,
		datab	 => datab_sig,
		result	 => result_sig
	);
