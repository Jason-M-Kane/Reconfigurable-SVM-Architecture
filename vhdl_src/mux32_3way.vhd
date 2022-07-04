library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity mux32_3way is
    Port ( ctrl    : in  STD_LOGIC_VECTOR(1 downto 0);
           data1   : in  STD_LOGIC_VECTOR (31 downto 0);
           data2   : in  STD_LOGIC_VECTOR (31 downto 0);
			  data3   : in  STD_LOGIC_VECTOR (31 downto 0);
           result  : out STD_LOGIC_VECTOR (31 downto 0));
end mux32_3way;

architecture behavioral of mux32_3way is
begin
--    result <= data1 when (ctrl = "10"),
--				data2		  when (ctrl = "01"),
--	         data3        when (ctrl = "00"),
--				 else data3;
with ctrl select
  result <= data3 when "00",
       data2 when "01",
       data1 when "10",
       data1 when "11";			 
				 
end behavioral;
