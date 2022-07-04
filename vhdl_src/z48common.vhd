library ieee; use ieee.std_logic_1164.all, ieee.std_logic_arith.all;

package z48common is

	function ceilDiv2(x: integer) return integer;
	function determineNumInterconnectSigs(x: integer) return integer;
	function calcPsumIndex(low1: integer range 1 to 100; high1: integer range 1 to 100; numClass: integer range 1 to 100) return integer;
	
	function num_adders(stage: integer; numFeatures: integer) return integer;	 
	function check_for_shiftreg(stage: integer; numFeatures: integer) return integer;
	function find_first_input(stage: integer; numFeatures: integer) return integer;
	function find_first_output(stage: integer; numFeatures: integer) return integer;
	function find_last_output(stage: integer; numFeatures: integer) return integer;


   function fact(x: integer) return integer;
   function log2c(x: integer) return integer;
   function ffs(x: std_logic_vector) return integer;
   function ffc(x: std_logic_vector) return integer;
   function int(x: std_logic_vector) return integer;
   function vec(x: integer; n: integer) return std_logic_vector;

   function all_bits_set(x: std_logic_vector) return boolean;
   function all_bits_clear(x: std_logic_vector) return boolean;
   function any_bit_set(x: std_logic_vector) return boolean;
   function any_bit_clear(x: std_logic_vector) return boolean;
end package z48common;

package body z48common is
   function fact(x: integer) return integer is
      variable ret: integer := 1;
   begin
      for i in x downto 2 loop
         ret := ret * i;
      end loop;
      return ret;
   end function;

   -- log2c rounds up when called for non-power-of-2 values; in other
   -- words, log2c(n) returns the number of bits to represent n as an
   -- unsigned binary value (or, the ceil of the floating-point log2)
   function log2c(x: integer) return integer is
      variable ret: integer := 0;
      variable i: integer := 1;
   begin
      -- this implementation may look clumsy, but it's intended to
      -- be evaluated only at compile time to determine static bounds;
      -- performance is irrelevant
      while(i < x) loop
         i := i * 2;
         ret := ret + 1;
      end loop;
      return ret;
   end function;
	
	function calcPsumIndex(low1: integer range 1 to 100; high1: integer range 1 to 100; numClass: integer range 1 to 100) return integer is
		variable sum   : integer := 0;
		variable index   : integer := 0;
	begin
		if( (( low1 = (numClass-1)) AND (high1 = numClass)) OR  
		    (( high1 = (numClass-1)) AND (low1 = numClass)) ) then
			index := 0;
		elsif(low1 < high1) then
			sum := ((numClass-1) - low1);
			sum := (sum*sum+sum)/2; --Triangular number sequence 
			index := sum + (high1-low1-1);
		else
			sum := ((numClass-1) - high1);
			sum := (sum*sum+sum)/2; --Triangular number sequence 
			index := sum + (low1-high1-1);
		end if;

      return (index); 
    end function;

    function ceilDiv2(x: integer) return integer is 
    begin
       return ((x+1) / 2);
    end function;
	

    function determineNumInterconnectSigs(x: integer) return integer is
        variable j   : integer := 0;
        variable k	 : integer := 0;
        variable sum : integer := 0;
    begin
        j := log2c(x);
        k := ceilDiv2(x);
		  sum := k+x;
        for  i in 2 to (j) loop
            k := ceilDiv2(k);
            sum := sum + k;
        end loop;
        return (sum-1); -- account for zero index;
    end function;

--    function check_odd_input(stage: integer; numFeatures: integer) is
--        variable num_pts_to_add  := numFeatures;
--        variable odd_index_total := numFeatures - 1;
--        variable odd_index       := -1;
--    begin
--        for i in 1 to stage loop
--            num_pts_to_add := num_pts_to_add / 2;
--            odd_index_total := 
--	    if( ((num_pts_to_add mod 2) /= 0) AND (num_pts_to_add > 1) ) then
--                num_pts_to_add := num_pts_to_add + 1;
--                odd_index := odd_index_total;
--            else
--                odd_index := -1;
--            end if;
--        end loop;
--        return ;
--    end function;




    --Returns the number of adder units to place in a particular stage
    function num_adders(stage: integer; numFeatures: integer) return integer is
        variable num_adders  : integer    := 0;
        variable num_inputs  : integer    := numFeatures;
    begin
        for i in 1 to stage loop

            -- Even # of inputs
            if((num_inputs mod 2) = 0) then
                num_inputs := num_inputs / 2;
                num_adders := num_inputs;
            else
                -- Odd # of inputs, subtract 1, then div by 2
                num_inputs := num_inputs - 1;
                num_inputs := num_inputs / 2;
                num_adders := num_inputs;
                num_inputs := num_inputs + 1;
            end if;
                
        end loop;
        return num_adders;
    end function;

	 
	function check_for_shiftreg(stage: integer; numFeatures: integer) return integer is
        variable num_inputs  : integer    := numFeatures;
		  variable shiftRegReq : integer    := 0;
    begin
        for i in 1 to stage loop

            -- Even # of inputs
            if((num_inputs mod 2) = 0) then
                num_inputs := (num_inputs / 2);
					 shiftRegReq := 0;               
            else
                -- Odd # of inputs, subtract 1, then div by 2
                num_inputs := num_inputs - 1;
                num_inputs := (num_inputs / 2);
                num_inputs := num_inputs + 1;
					 shiftRegReq := 1;
            end if;
                
        end loop;
        return shiftRegReq;
    end function;


    --Returns the index of the first input at a given stage 1 to N
    function find_first_input(stage: integer; numFeatures: integer) return integer is
        variable num_inputs  : integer    := numFeatures;
        variable index       : integer    := 0;
    begin
        for i in 2 to stage loop

            index := index + num_inputs;

            -- Even # of inputs
            if((num_inputs mod 2) = 0) then
                num_inputs := (num_inputs / 2);                
            else
                -- Odd # of inputs, subtract 1, then div by 2
                num_inputs := num_inputs - 1;
                num_inputs := (num_inputs / 2);
                num_inputs := num_inputs + 1;
            end if;
                
        end loop;
        return index;
    end function;


	 
    --Returns the index of the first output at a given stage 1 to N
    function find_first_output(stage: integer; numFeatures: integer) return integer is
        variable num_adders   : integer   := 0;
        variable num_inputs   : integer   := numFeatures;
        variable index        : integer   := 0;
    begin
        for i in 1 to stage loop

            index := index + num_inputs;

            -- Even # of inputs
            if((num_inputs mod 2) = 0) then
                num_inputs := (num_inputs / 2);                
            else
                -- Odd # of inputs, subtract 1, then div by 2
                num_inputs := num_inputs - 1;
                num_inputs := (num_inputs / 2);
                num_inputs := num_inputs + 1;
            end if;
                
        end loop;
        return index;
    end function;

    --Returns the index of the last output at a given stage 1 to N
    function find_last_output(stage: integer; numFeatures: integer) return integer is
        variable num_adders   : integer   := 0;
        variable num_inputs   : integer   := numFeatures;
        variable index        : integer   := numFeatures-1;
    begin
        for i in 1 to stage loop

            -- Even # of inputs
            if((num_inputs mod 2) = 0) then
                num_inputs := (num_inputs / 2);                
            else
                -- Odd # of inputs, subtract 1, then div by 2
                num_inputs := num_inputs - 1;
                num_inputs := (num_inputs / 2);
                num_inputs := num_inputs + 1;
            end if;

            index := index + num_inputs;
                
        end loop;
        return index;
    end function;
	


   function ffs(x: std_logic_vector) return integer is begin
      for i in x'low to x'high loop
         if(x(i) = '1') then
            return i;
         end if;
      end loop;
      return x'low;
   end function;
   function ffc(x: std_logic_vector) return integer is begin
      for i in x'low to x'high loop
         if(x(i) = '0') then
            return i;
         end if;
      end loop;
      return x'low;
   end function;

   function int(x: std_logic_vector) return integer is begin
      return conv_integer(unsigned(x));
   end function;
   function vec(x: integer; n: integer) return std_logic_vector is begin
      return conv_std_logic_vector(x, n);
   end function;

   function all_bits_set(x: std_logic_vector) return boolean is begin
      return x = (x'range => '1');
   end function;
   function all_bits_clear(x: std_logic_vector) return boolean is begin
      return x = (x'range => '0');
   end function;
   function any_bit_set(x: std_logic_vector) return boolean is begin
      return not all_bits_clear(x);
   end function;
   function any_bit_clear(x: std_logic_vector) return boolean is begin
      return not all_bits_set(x);
   end function;
end package body;
