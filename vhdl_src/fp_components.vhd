-------------------------------------------------------
-- File Name   : limb_feature_pkg.vhd
-- Function    : Defines emg / load cell types
-------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
    
package fp_components is


	type floatArray is array (integer range <>) of std_logic_vector(31 downto 0);

	constant FP32VAL_0_0	    : std_logic_vector(31 downto 0) := X"00000000";
	constant FP32VAL_1_0	    : std_logic_vector(31 downto 0) := X"3F800000";
	constant FP32VAL_NEG_1_0 : std_logic_vector(31 downto 0) := X"BF800000";
	constant FP32VAL_2_0	    : std_logic_vector(31 downto 0) := X"40000000";


	constant NUM_FPSUB_CYCLES   : integer := 7;
	constant NUM_FPADD_CYCLES   : integer := 7;
	constant NUM_FPMULT_CYCLES  : integer := 5;
	constant NUM_EXP_CYCLES     : integer := 17;
	constant NUM_LOG_CYCLES     : integer := 21;
	constant NUM_FPDIV_CYCLES	 : integer := 6;


	--FP32 Addition or Subtraction Unit
	component addSubFP32
	PORT
	(
		aclr		: IN STD_LOGIC ;
		add_sub	: IN STD_LOGIC ;
		clk_en	: IN STD_LOGIC ;
		clock		: IN STD_LOGIC ;
		datab		: IN STD_LOGIC_VECTOR (31 DOWNTO 0);
		dataa		: IN STD_LOGIC_VECTOR (31 DOWNTO 0);
		result	: OUT STD_LOGIC_VECTOR (31 DOWNTO 0)
	);
	end component;
	
	--FP32 Multiplication Unit
	COMPONENT fp32mult
	PORT (
			aclr		: IN STD_LOGIC ;
			clk_en	: IN STD_LOGIC ;
			clock		: IN STD_LOGIC ;
			datab		: IN STD_LOGIC_VECTOR (31 DOWNTO 0);
			dataa		: IN STD_LOGIC_VECTOR (31 DOWNTO 0);
			result	: OUT STD_LOGIC_VECTOR (31 DOWNTO 0)
	);
	END COMPONENT;

	--FP32 Division Unit
	COMPONENT fp32div
	PORT (
			clk_en	: IN STD_LOGIC ;
			clock		: IN STD_LOGIC ;
			datab		: IN STD_LOGIC_VECTOR (31 DOWNTO 0);
			dataa		: IN STD_LOGIC_VECTOR (31 DOWNTO 0);
			result	: OUT STD_LOGIC_VECTOR (31 DOWNTO 0)
	);
	END COMPONENT;
	
	--FP32 Exponential Unit
	COMPONENT fp32exp
	PORT
	(
		clk_en	: IN STD_LOGIC;
		clock		: IN STD_LOGIC;
		data		: IN STD_LOGIC_VECTOR(31 downto 0);
		result	: OUT STD_LOGIC_VECTOR(31 downto 0)
	);
	END COMPONENT fp32exp;

	--FP32 Log Unit
	COMPONENT fp32log
	PORT
	(
		clk_en	: IN STD_LOGIC;
		clock		: IN STD_LOGIC;
		data		: IN STD_LOGIC_VECTOR(31 downto 0);
		result	: OUT STD_LOGIC_VECTOR(31 downto 0)
	);
	END COMPONENT fp32log;

	--FP32 Greater Than Compare Unit
	COMPONENT fp32_compare_gt
	PORT (
			aclr		: IN STD_LOGIC;
			clk_en          : IN STD_LOGIC;
			clock		: IN STD_LOGIC;
			datab		: IN STD_LOGIC_VECTOR (31 DOWNTO 0);
			dataa		: IN STD_LOGIC_VECTOR (31 DOWNTO 0);
			agb		: OUT STD_LOGIC
	);
	END COMPONENT;
end;


 
 
package body fp_components is


 

 
end package body;
