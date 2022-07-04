library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity fp_negate is
    Port ( clock	 : in STD_LOGIC;
			  dataIn  : in   STD_LOGIC_VECTOR (31 downto 0);
           dataOut : out  STD_LOGIC_VECTOR (31 downto 0);
			  negateOpt  : in STD_LOGIC
			  );
end fp_negate;

architecture behavioral of fp_negate is
begin

	fp_negateProcess: process(clock)
	begin

	if(rising_edge(clock)) then
		-- Output the absolute value of the incoming FP32 data
		if(negateOpt = '1') then
			dataOut <= not(dataIn(31)) & dataIn(30 downto 0);
		else
			dataOut <= dataIn;
		end if;
   end if;
	end process;
	
end behavioral;
