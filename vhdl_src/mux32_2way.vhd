library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity mux32_2way is
    Port ( ctrl    : in  STD_LOGIC;
           data1   : in  STD_LOGIC_VECTOR (31 downto 0);
           data2   : in  STD_LOGIC_VECTOR (31 downto 0);
           result  : out STD_LOGIC_VECTOR (31 downto 0));
end mux32_2way;

architecture behavioral of mux32_2way is
begin
    result <= data1 when (ctrl = '1') else data2;
end behavioral;
