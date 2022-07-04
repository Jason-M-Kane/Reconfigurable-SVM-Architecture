-------------------------------------------------------
-- File Name   : limb_feature_pkg.vhd
-- Function    : Defines emg / load cell types
-------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
    
package limb_feature_pkg is


constant MODE_20MS	: std_logic := '0';
constant MODE_50MS	: std_logic := '1';

type emgFeatRec is record
  		mav: std_logic_vector(31 downto 0);
  		len: std_logic_vector(31 downto 0);
  		zeroX: std_logic_vector(31 downto 0);
		turns: std_logic_vector(31 downto 0);
end record;
type emgFeatureArray is array (0 to 6) of emgFeatRec;



-- Put in a package
type ldCellFeatRec is record
  		min: std_logic_vector(31 downto 0);
  		max: std_logic_vector(31 downto 0);
  		avg: std_logic_vector(31 downto 0);
end record;
type ldCellFeatureArray is array (0 to 5) of ldCellFeatRec;

--type floatArray is array (integer range <>) of std_logic_vector(31 downto 0);

 
end;


 
 
package body limb_feature_pkg is


 

 
end package body;





