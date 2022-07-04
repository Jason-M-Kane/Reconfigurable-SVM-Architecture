library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity abs_signDetect is
    Port ( clock	 : in STD_LOGIC;
			  dataIn  : in   STD_LOGIC_VECTOR (31 downto 0);
           dataOut : out  STD_LOGIC_VECTOR (31 downto 0);
			  pwr_odd : in STD_LOGIC;
           signModify : out STD_LOGIC
			  );
end abs_signDetect;

architecture behavioral of abs_signDetect is
begin

	abs_signDetectProcess: process(clock)
	begin

	if(rising_edge(clock)) then
		-- Output the absolute value of the incoming FP32 data
		dataOut <= '0' & dataIn(30 downto 0);
		
		-- If the FP32 data was negative, and D is an odd power, set this
		if((dataIn(31) = '1') AND (pwr_odd = '1')) then
			signModify <= '1';
		else
			signModify <= '0';
		end if;
   end if;
	end process;
end behavioral;
