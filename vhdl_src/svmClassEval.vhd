-------------------------------------------------------------------------------
-- Jason Kane
--
-- SVM Class Evaluation
--
-- Input:  
-- Output: 
--
-- This file contains 3 processes that control the SVM calculation and
-- one process to control writing to coefficient and rho memory
--
-- The first process first controls the summation of the coefficient multiplications
-- Two summations are stored for each class comparison: (x vs y) and ((y vs x) - rho)
-- The results are stored in a 42 entry RAM (7 class)
-- When there are fewer classes, less entries are used.  The maximum number of 
-- classes allowed by this implementation is 7.
--
-- The second process sums each set of 2 class comparisons together.
-- The RAM is read back from, and like comparisons are added
-- For example, 1v2 and 2v1, 1v3 and 3v1, etc. 
-- The addition is pipelined and a valid signal follows through the pipeline to 
-- notify the 3rd process when valid data exits the pipe.
--
-- In the third process a floating point comparision is made to see if the result 
-- of the 2nd process' addition is greater than 0.  If greater,
-- then the lower class gets a vote.  Otherwise the higher numbered class gets a vote.
-- After voting takes place, the class with the greatest number of votes is declared 
-- the winner.  This class is reported to the higher level module.
-------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
USE IEEE.std_logic_unsigned.all;
use IEEE.NUMERIC_STD.ALL;

LIBRARY altera_mf;
USE altera_mf.altera_mf_components.all;

use work.fp_components.all;
use work.z48common.all;




entity svmClassEval is
        generic(
		NUM_CLASS_MAX           : integer;  -- Maximum Number of Classes the Hardware Will Handle ; WAS Fixed at 7
		NUM_MODELS              : integer;  -- Number of simultaneous models to support
		TOTAL_NUM_SV            : integer;  -- Maximum # of SV vectors to be stored (for all models)
		MAX_SV_IN_LRG_MODEL     : integer  -- Maximum # of SV vectors to be stored in the largest model
        );
	port(
	
		--Clock and Reset
		class_clock                                     : in  STD_LOGIC;
		class_reset                                     : in  STD_LOGIC;  -- Reset = '1', Not in Reset = '0'
		class_restart                                   : in  STD_LOGIC;	-- Restart for a new class evaluation when '1'
				
		--Input Kernel Values
		kernelIndex                                     : buffer std_logic_vector( (log2c(MAX_SV_IN_LRG_MODEL+1)-1) downto 0);
		kernelValue                                     : in std_logic_vector(31 downto 0);
		
		--Model to be used
		model_select                                    : in integer range 0 to (NUM_MODELS-1);
		
		-- Databus Input for SVM Coefficient and Rho RAMs Databus
		coeffAndRhoDataBus				: in std_logic_vector(31 downto 0);
		coeff_rho_WrStateRst				: in std_logic;   -- Restart RAM Write state machine when '1'
		coeff_rho_clock					: in std_logic;   -- Write clock for coefficent and Rho RAMs
		coeff_rho_termSig                               : in std_logic;
		coeff_rho_dvalid                                : in std_logic;
		coeff_rho_dack                                  : out std_logic;
		forceCoeffIndexIncr				: in std_logic;
		
		--Output Interface for Calculated Class Values
		classEvalComplete                               : out std_logic;
		classOut                                        : out std_logic_vector(15 downto 0)
	);
end entity svmClassEval;






architecture mixed of svmClassEval is

	

	attribute keep: boolean;
	
	
	constant NUM_CYCLES_MULTACCUM   : integer := 13;
	constant FINAL_COMPARE_STAGES   : integer := 7;


	constant numRhoRamWords		: integer := (((NUM_CLASS_MAX*(NUM_CLASS_MAX-1))/2) * NUM_MODELS);
	constant numcoeffRamWords	: integer := 1 + NUM_MODELS + (NUM_CLASS_MAX*NUM_MODELS) + TOTAL_NUM_SV;
	constant numPsumRamWords 	: integer := (NUM_CLASS_MAX*(NUM_CLASS_MAX-1)) / 2;	--KANE ADDED
	constant rhoRamHighBit          : integer := log2c(numRhoRamWords) -1;
	constant coeffRamHighBit        : integer := log2c(numcoeffRamWords) - 1;	
	constant psumRamHighBit         : integer := log2c(numPsumRamWords) - 1;

	constant max_possible_votes	: integer := NUM_CLASS_MAX-1;
	constant voteCntHighBit		: integer := log2c(max_possible_votes+1) - 1;  -- +1 accounts for zero 
	
	type wrCoeffRhoState_Type is (wrIdleState, waitForEndResetPulse, 
					wait_For_Rho_Dvalid_Or_Term , writeRhoValue,
					rho_wait_for_dvalid_low, wait_For_Term_Low_1, 
					wait_For_Coeff_Dvalid_Or_Term, writeCoeffValue, 
					ceoff_wait_for_dvalid_low, wait_For_Term_Low_2);
	type evalState_TYPE is (idleStateA, idleStateB, rdOffset, rdNumCoeffInClass, loadNegRhoValues, 
				initiateMultAccum,accumRemainingData_PTA,accumRemainingData_PTB);
	type countState_TYPE is(zeroValidBits, initState, idleState, storeClassCompareData, waitForPsumWriteComplete, waitRegFullZero);
	type voteArray is array(1 to NUM_CLASS_MAX) of std_logic_vector(voteCntHighBit downto 0);
	type voteState_TYPE is (waitForRestart_Pulse0, waitForRestart_Pulse1,  
                                waitForValidCompare, outputResult);

	type classCounters_Type is array(FINAL_COMPARE_STAGES downto 0) of integer range 0 to (NUM_CLASS_MAX+1);

				
	signal evalState : evalState_TYPE;
	signal wrState   : wrCoeffRhoState_Type;
	signal countState: countState_TYPE;
	
	-- RAM Signals
	signal c_ram_select             : integer range 0 to (NUM_CLASS_MAX-2);
	signal initNumCoefRam_Flg 		: std_logic;
	signal numCoefRam					  : integer range 0 to (NUM_CLASS_MAX); --really min 2
	signal coeffRdIndex		: std_logic_vector(coeffRamHighBit downto 0);
	signal coeffWrIndex		: std_logic_vector(coeffRamHighBit downto 0);
	signal coeffRdData		: floatArray(0 to NUM_CLASS_MAX-2);
	signal rhoRdIndex               : std_logic_vector(rhoRamHighBit downto 0);
	signal rhoWrIndex               : std_logic_vector(rhoRamHighBit downto 0);
	signal rhoRdData                : std_logic_vector(31 downto 0);
	signal psumDataIn               : std_logic_vector(32 downto 0);
	signal psumRdIndex		: std_logic_vector(psumRamHighBit downto 0);
	signal psumWrIndex		: std_logic_vector(psumRamHighBit downto 0);
	signal ps_wren                  : std_logic;
	signal partialSumOutput	: std_logic_vector(32 downto 0);
	
	signal coeffRAM_wren		: std_logic_vector(0 to NUM_CLASS_MAX-2);
	signal rhoRAM_wren		: std_logic;
	
	-- Class Information Signals
	signal coefModelStartIndex	:  std_logic_vector(coeffRamHighBit downto 0);

	-- Pipeline Signals
	signal coeff_pipe_enable : std_logic;
	signal coeff_multOutput	 : floatArray(0 to (NUM_CLASS_MAX-2));
	signal coeff_addOutput	 : floatArray(0 to (NUM_CLASS_MAX-2));
	signal accum_inputA	 : floatArray(0 to (NUM_CLASS_MAX-2));
	signal storedSum         : floatArray(0 to (NUM_CLASS_MAX-2));
	signal savedMAC		 : floatArray(0 to (NUM_CLASS_MAX-2));
	
	-- Signals used for coefficient multiply/accum process
	signal svmModelOffset		: std_logic_vector(coeffRamHighBit downto 0);
	signal svmNumClass              : std_logic_vector(31 downto 0);
	signal numCoeffinClass          : std_logic_vector(31 downto 0);
	signal numClassLeft             : std_logic_vector(31 downto 0);
	signal rhoTarget                : std_logic_vector(31 downto 0);
	signal rhoCount                 : integer range 0 to NUM_CLASS_MAX;
	signal rhoCountInit             : integer range 0 to NUM_CLASS_MAX;
	signal cindex                   : integer range 0 to (NUM_CLASS_MAX-1);
	signal cntr_to_valid_data 		  : integer range 0 to 31;
	
	signal coeffPerSV               : integer range 0 to (NUM_CLASS_MAX);
	signal coeffPerSVCpy           : integer range 0 to (NUM_CLASS_MAX);

	-- Partial Summation Signals				
	signal lastSumFlgIn 	:	std_logic;
	signal zeroFlg 		:	std_logic;
	signal targetCount	: integer range 0 to NUM_CLASS_MAX+1;
	signal leftCount	: integer range 0 to NUM_CLASS_MAX+1;
	signal rightCount	: integer range 0 to NUM_CLASS_MAX+1;
	signal beginValidAdd	: std_logic;
	signal lowCompareStart	: integer range 0 to NUM_CLASS_MAX+1;
	signal highCompareStart : integer range 0 to NUM_CLASS_MAX+1;

	--Comparison Valid shift registers
	signal validShftReg		: std_logic_vector(FINAL_COMPARE_STAGES downto 0);
	signal lastSumShftReg		: std_logic_vector(FINAL_COMPARE_STAGES downto 0);
	signal lowCompareShftReg	: classCounters_Type;
	signal upperCompareShftReg	: classCounters_Type;

	-- Final Summation Signals
	signal finalAddInputA		: std_logic_vector(31 downto 0);
	signal finalAddInputB		: std_logic_vector(31 downto 0);
	signal sumOut                   : std_logic_vector(31 downto 0);
	signal compare_out              : std_logic;


	--Voting related signals
	alias compare_valid : std_logic is validShftReg(0);
	alias cmpLowOut  : integer range 0 to (NUM_CLASS_MAX+1) is lowCompareShftReg(0);
	alias cmpHighOut : integer range 0 to (NUM_CLASS_MAX+1) is upperCompareShftReg(0);
	alias lastSumFlgOut : std_logic is lastSumShftReg(0);
	signal voteState 		: voteState_TYPE;
	signal electedClass             : integer range 1 to NUM_CLASS_MAX;
	signal voteCnt			: voteArray;
	signal maxVotes                 : std_logic_vector(voteCntHighBit downto 0);



	signal saveRegFullAck	: std_logic;
	signal saveRegFull	: std_logic;
	signal select_kval_zero	: std_logic;
	--signal lastStoreFlg 	: std_logic;
	signal multInputA:std_logic_vector(31 downto 0);
	signal initiateFinalSum : std_logic;


	
	-- RAM Signals
--	attribute keep of c_ram_select             :  signal is true;
--	attribute keep of coeffRdIndex		:  signal is true;
--	attribute keep of coeffRdData		:  signal is true;
--	attribute keep of coeffWrIndex		:  signal is true;
--	attribute keep of coeffRAM_wren		:  signal is true;
--	attribute keep of rhoRdIndex               :  signal is true;
--	attribute keep of rhoRdData                :  signal is true;
--	attribute keep of rhoWrIndex               :  signal is true;
--	attribute keep of coeffAndRhoDataBus	: signal is true;
--	attribute keep of rhoRAM_wren		:  signal is true;
--	attribute keep of psumRdIndex		:  signal is true;
--	attribute keep of partialSumOutput	:  signal is true;
--	attribute keep of psumWrIndex		:  signal is true;
--	attribute keep of psumDataIn               :  signal is true;
--	attribute keep of ps_wren                  :  signal is true;
--	attribute keep of forceCoeffIndexIncr	: signal is true;
--	attribute keep of coeff_rho_WrStateRst 	: signal is true;
--	attribute keep of coeff_rho_clock	: signal is true;
--	attribute keep of coeff_rho_termSig	: signal is true;
--	attribute keep of coeff_rho_dvalid	: signal is true;
--	attribute keep of coeff_rho_dack	: signal is true;
--
--	-- Pipeline Signals
--	attribute keep of kernelIndex	:   signal is true;
--	attribute keep of kernelValue	:   signal is true;
--	attribute keep of coeff_pipe_enable 	:  signal is true;
--	attribute keep of coeff_multOutput	 :  signal is true;
--	attribute keep of accum_inputA	 	:  signal is true;
--	attribute keep of storedSum         	:  signal is true;
--	attribute keep of coeff_addOutput	 :  signal is true;
--	attribute keep of savedMAC		 :  signal is true;
--	attribute keep of saveRegFull:   signal is true;
--	attribute keep of saveRegFullAck:   signal is true;
--	attribute keep of select_kval_zero:   signal is true;
--	
--	-- Signals used for coefficient multiply/accum process
--	attribute keep of class_restart :   signal is true;
--	attribute keep of model_select	:   signal is true;
--	attribute keep of coefModelStartIndex	:   signal is true;
--	attribute keep of svmModelOffset	:  signal is true;
--	attribute keep of svmNumClass              :  signal is true;
--	attribute keep of numCoeffinClass          :  signal is true;
--	attribute keep of numClassLeft             :  signal is true;
--	attribute keep of rhoTarget                :  signal is true;
--	attribute keep of rhoCount                 :  signal is true;
--	attribute keep of rhoCountInit             :  signal is true;
--	attribute keep of cntr_to_valid_data 	: signal is true;
--	attribute keep of coeffPerSV               : signal is true;
--	attribute keep of classEvalComplete	:   signal is true;
--	attribute keep of classOut	:   signal is true;
--
--	--attribute keep of lastStoreFlg       : signal is true;
--	attribute keep of cindex                   : signal is true;
--
--	--Comparison Valid shift register
--	attribute keep of validShftReg	:   signal is true;
--	attribute keep of lastSumShftReg	:   signal is true;
--	attribute keep of lowCompareShftReg	:   signal is true;
--	attribute keep of upperCompareShftReg	:   signal is true;
--	attribute keep of sumOut	:   signal is true;
--	attribute keep of compare_out	:   signal is true;
--	attribute keep of compare_valid	:   signal is true;
--	attribute keep of cmpLowOut	:   signal is true;
--	attribute keep of cmpHighOut	:   signal is true;
--	attribute keep of maxVotes	:   signal is true;
--	attribute keep of voteCnt	:   signal is true;
--	attribute keep of lastSumFlgOut	:   signal is true;
	
	
begin

	------------------------------------------------------------------------------------
	-- Assemble the hardware to perform a FP pipelined Coefficient Multiply/Summation --
	------------------------------------------------------------------------------------
	coeffCalculateUnit: for i in 0 to (NUM_CLASS_MAX-2) generate
	begin
	
			multUnit: fp32mult PORT MAP (
				aclr	 	=> class_reset,
				clk_en          => coeff_pipe_enable,
				clock	 	=> class_clock,
				dataa	 	=> multInputA, -- WAS kernelValue
				datab	 	=> coeffRdData(i),
				result          => coeff_multOutput(i)
			);
			addUnit: addSubFP32 PORT MAP (
				aclr	 	=> class_reset,
				add_sub         => '1',
				clk_en          => coeff_pipe_enable,
				clock	 	=> class_clock,
				dataa	 	=> accum_inputA(i),
				datab	 	=> storedSum(i),
				result          => coeff_addOutput(i)
			);	
	end generate coeffCalculateUnit;	
	


	-- MUX BETWEEN 0 and kernel Value
	mux2 : entity WORK.mux32_2way(behavioral)
	PORT MAP (
		ctrl		=> select_kval_zero,
		data1	 	=> kernelValue,
		data2	 	=> X"00000000",
		result	=> multInputA
	);


        --------------------------------------------
        --          Coefficient RAM
	-- Size of Each = 1 + #Models + NumClass*NumModels + Num SV
        --------------------------------------------
        --
        -- NUMCLASS-1 coefficients exist
        --
	-- Format is:
	-- =========================
	-- # Classes
	-- Offset to Start of Model 1 Data
	-- Offset to Start of Model 2 Data
	-- Offset to Start of Model 3 Data
	-- Offset to Start of Model ... Data
	-- Offset to Start of Model Data
	-- #SV in Model 1 Class 1
	-- Model 1 Class 1 Coefficients[] 
	-- #SV in Model 1 Class 2
	-- Model 1 Class 2 Coefficients[] 
	-- ...
	-- #SV in Model 1 Class N
	-- Model 1 Class N Coefficients[]
	-- #SV in Model 2 Class 1
	-- Model 2 Class 1 Coefficients[]
	-- #SV in Model 2 Class 2
	-- Model 2 Class 2 Coefficients[]
	-- ...
	-- #SV in Model 2 Class N
	-- Model 2 Class N Coefficients[]
	-- ...
	-- #SV in Model Last Class 1
	-- Model Last Class 1 Coefficients[]
	-- #SV in Model Last Class 2
	-- Model Last Class 2 Coefficients[]
	-- ...
	-- #SV in Model Last Class N
	-- Model Last Class N Coefficients[]
	-- ==========================
	--
	-------------------------------------------------------------------------------------
	-- Note:  Each SV has its (up to K-1) coefficients stored across (K-1) 32-bit RAMs.
	-- The #Classes and #SV are duplicated across the N 32-bit RAMs to make
	-- indexing easier.
	-------------------------------------------------------------------------------------
	GEN_SVM_COEFF_RAM: for i in 0 to (NUM_CLASS_MAX-2) generate
	begin
		coeffRamUnit: altsyncram
		generic map(
			address_aclr_b => "NONE",
			address_reg_b => "CLOCK1",
			clock_enable_input_a => "BYPASS",
			clock_enable_input_b => "BYPASS",
			clock_enable_output_b => "BYPASS",
			intended_device_family => "Stratix V",
			lpm_type => "altsyncram",
			numwords_a => numcoeffRamWords,
			numwords_b => numcoeffRamWords,
			operation_mode => "DUAL_PORT",
			outdata_aclr_b => "NONE",
			outdata_reg_b => "UNREGISTERED",
			power_up_uninitialized => "FALSE",
			widthad_a => coeffRamHighBit+1,
			widthad_b => coeffRamHighBit+1,
			width_a => 32,
			width_b => 32,
			width_byteena_a => 1
		)
		PORT MAP (
			address_a => coeffWrIndex,
			clock0 => not coeff_rho_clock,
			data_a => coeffAndRhoDataBus,
			wren_a => coeffRAM_wren(i),
			address_b => coeffRdIndex,
			clock1 => not class_clock,
			q_b => coeffRdData(i)
		);
	end generate GEN_SVM_COEFF_RAM;


	

	------------------------------
	-- Rho RAM
	------------------------------
        -- 1 Rho Exists for each comparison.  Total of ((#Classes * (#Classes-1)) / 2) comparisons
	-- Size of Rho RAM is this total # multiplied by the number of models
	--
	-- Model 1 Rho[0]
	-- Model 1 Rho[1]
	-- Model 1 Rho[...]
	-- Model 1 Rho[N]
	-- Model 2 Rho[0]
	-- Model 2 Rho[1]
	-- Model 2 Rho[...]
	-- Model 2 Rho[N]
        -- ...
        -- Model Last Rho[N]
	-------------------------------
	rhoRamUnit : altsyncram
	generic map(
		address_aclr_b => "NONE",
		address_reg_b => "CLOCK1",
		clock_enable_input_a => "BYPASS",
		clock_enable_input_b => "BYPASS",
		clock_enable_output_b => "BYPASS",
		intended_device_family => "Stratix V",
		lpm_type => "altsyncram",
		numwords_a => numRhoRamWords,
		numwords_b => numRhoRamWords,
		operation_mode => "DUAL_PORT",
		outdata_aclr_b => "NONE",
		outdata_reg_b => "UNREGISTERED",
		power_up_uninitialized => "FALSE",
		widthad_a => rhoRamHighBit+1,
		widthad_b => rhoRamHighBit+1,
		width_a => 32,
		width_b => 32,
		width_byteena_a => 1
		)
	PORT MAP (
		address_a => rhoWrIndex,
		clock0 => not coeff_rho_clock,
		data_a => coeffAndRhoDataBus,
		wren_a => rhoRAM_wren,
		address_b => rhoRdIndex,
		clock1 => not class_clock,
		q_b => rhoRdData
	);


	----------------------------------------------------------
	-- Partial Sum RAM
	----------------------------------------------------------
        -- # Entries = #Classes * (#Classes-1)
	-- Partial Coefficient Summation RAM
	--
	-- Storage Format (7-Class Example):  
        --          1vs2, 1vs3, 1vs4, 1vs5, 1vs6, 1vs7,
	--          2vs1, 2vs3, 2vs4, 2vs5, 2vs6, 2vs7,
	--          ...
	--          7vs1, 7vs2, 7vs3, 7vs4, 7vs5, 7vs6
	----------------------------------------------------------
	partialSumRamUnit : altsyncram
	generic map(
		address_aclr_b => "NONE",
		address_reg_b => "CLOCK1",
		clock_enable_input_a => "BYPASS",
		clock_enable_input_b => "BYPASS",
		clock_enable_output_b => "BYPASS",
		intended_device_family => "Stratix V",
		lpm_type => "altsyncram",
		numwords_a => numPsumRamWords,
		numwords_b => numPsumRamWords,
		operation_mode => "DUAL_PORT",
		outdata_aclr_b => "NONE",
		outdata_reg_b => "UNREGISTERED",
		power_up_uninitialized => "FALSE",
		widthad_a => psumRamHighBit+1,
		widthad_b => psumRamHighBit+1,
		width_a => 33,
		width_b => 33,
		width_byteena_a => 1
		)
	PORT MAP (
		address_a => psumWrIndex,
		clock0 => not class_clock,
		data_a => psumDataIn,
		wren_a => ps_wren,
		address_b => psumRdIndex,
		clock1 => not class_clock,
		q_b => partialSumOutput
	);	
	
	


	---------------------------------------------------------------------------------------------------------
	-- This process remains idle until class_restart is pulsed high
	--
	-- This process first controls the summation of the coefficient multiplications
	-- And stores the results in a XX entry RAM (Size bassed on #classes max).  Less slots are used if there are fewer
	-- classes.  -Rho is added to one of the two comparison values during this process during the
	-- initialization of the summation register.  This saves needing an extra subtraction later.
	--
	-- After summing, the process then goes to the idle state until class_restart is pulsed again.
	------------------------------------------------------------------------------------------------------
	classEvalPipelineCtrl: process(class_clock)

	begin

	if(rising_edge(class_clock)) then
		if(class_reset = '1') then
			coeff_pipe_enable <= '0';
			select_kval_zero <= '0';
			coeffRdIndex <= (others => '0');
			saveRegFull <= '0';
			--lastStoreFlg <= '0';
			evalState <= idleStateA;
		else
			-- Handle Voting and Partial Sum Saves
			initiateFinalSum <= '0';
			if(saveRegFullAck = '1') then
				saveRegFull <= '0';
			--	if(lastStoreFlg = '1') then
			--		lastStoreFlg <= '0';
			--	end if;
			end if;
		
			case evalState is
			
				when idleStateA =>
					
					if(class_restart = '0') then
						coeffRdIndex <= (others => '0');
						evalState <= idleStateB;
					end if;
					
				when idleStateB =>
					if(class_restart = '1') then
						-- Load the number of classes in the current model
						-- And begin to request the model start address for the coefficients
						svmNumClass  <= coeffRdData(0);
						numClassLeft <= coeffRdData(0);
						rhoTarget    <= (coeffRdData(0)-1);
						rhoCountInit <= 0;
						kernelIndex  <= (others => '0');
						

						-- Get Coeff Offset Index and Rho Read Index
						coeffRdIndex <= vec(model_select+1,coeffRdIndex'length);
						rhoRdIndex   <= vec(model_select*(((NUM_CLASS_MAX)*(NUM_CLASS_MAX-1))/2),rhoRdIndex'length);

						-- Determine # Coeff per SV (MAX_Class through 2 class)
						if((coeffRdData(0) <= NUM_CLASS_MAX) AND (coeffRdData(0) > 1)) then
							coeffPerSV <= int(coeffRdData(0)) - 1;
						else
							coeffPerSV <= 0;
						end if;
					
						evalState <= rdOffset;
					end if;

				when rdOffset =>
					if(saveRegFull = '0') then	-- Ensure last round of summations are done
						initiateFinalSum <= '1';
						coeffRdIndex <= coeffRdData(0)(coeffRdIndex'length-1 downto 0);
						evalState <= rdNumCoeffInClass;
					end if;
				
				-- Read in the Number of Coefficients for this Class
				when rdNumCoeffInClass =>
					numCoeffinClass <= coeffRdData(0);
					rhoCount <= rhoCountInit;
					
					--Init class summed values to 0
					for l in 0 to (NUM_CLASS_MAX-2) loop
						storedSum(l) <= (others => '0');
					end loop;
					evalState <= loadNegRhoValues;
	
				--Load (-)Rho Values
				when loadNegRhoValues =>
					if(rhoCount = rhoTarget) then
						rhoCountInit <= rhoCountInit + 1;
						coeffRdIndex <= coeffRdIndex + 1;
						if(numCoeffinClass > 0) then
							numCoeffinClass <= numCoeffinClass - coeffPerSV;
							select_kval_zero <= '1';
						else
							numCoeffinClass <= (others => '0');
							select_kval_zero <= '0';
						end if;
						coeff_pipe_enable <= '1';
						cntr_to_valid_data <= 0;
						
						for i in 0 to (NUM_CLASS_MAX-2) loop -- dont know if this is needed
							accum_inputA(i) <= X"00000000";
						end loop;
						
						evalState <= initiateMultAccum;
					else
						storedSum(rhoCount) <= rhoRdData;
						rhoRdIndex <= rhoRdIndex + 1;
						rhoCount <= rhoCount + 1;
					end if;
					
				-- Perform Pipelined Multiply Accumulate
				when initiateMultAccum =>

					--Supply a new kernel and coefficient index on each clock cycle
					kernelIndex <= kernelIndex + 1;
					coeffRdIndex <= coeffRdIndex + 1;
					
					--Adjust the number of coefficients left
					if(numCoeffinClass > 0) then
						numCoeffinClass <= numCoeffinClass - coeffPerSV;
					else
						-- CHECK IF THERE IS Any class data left
						-- if no more class data left, see if there are any classes left
						-- if neither, partial summation is done
						select_kval_zero <= '0';   -- SET ALL KERNEL INDEX INPUTS to zero
						numClassLeft <= numClassLeft - 1;
						evalState <= accumRemainingData_PTA;
					end if;

					--Initialize accumulate pipeline
					if(cntr_to_valid_data = NUM_CYCLES_MULTACCUM) then
						for l in 0 to (NUM_CLASS_MAX-2) loop
							storedSum(l) <= coeff_addOutput(l);
						end loop;
					elsif(cntr_to_valid_data > 5) then	--Allow 1st Rho Value to get added in
						for l in 0 to (NUM_CLASS_MAX-2) loop
							storedSum(l) <= X"00000000";
						end loop;
						cntr_to_valid_data <= cntr_to_valid_data + 1;
					else
						cntr_to_valid_data <= cntr_to_valid_data + 1;
					end if;

					--Forward multiply output to accumulator unit
					for i in 0 to (NUM_CLASS_MAX-2) loop
						accum_inputA(i) <= coeff_multOutput(i);
					end loop;


				--Flush out any good data remaining in the multiplier.
				--On the next state, only data in the adder will remain for accumulation
				when accumRemainingData_PTA =>
					if(cntr_to_valid_data = 6) then
						for l in 0 to (NUM_CLASS_MAX-2) loop
							storedSum(l) <= X"00000000";
						end loop;
					end if;
				
					-- only write to stored sum if >= 0xD cycles		
					if(cntr_to_valid_data >= NUM_CYCLES_MULTACCUM) then
						for l in 0 to (NUM_CLASS_MAX-2) loop
							storedSum(l) <= coeff_addOutput(l);
						end loop;
					end if;
				
					for l in 0 to (NUM_CLASS_MAX-2) loop
						accum_inputA(l) <= coeff_multOutput(l);
--						storedSum(l)    <= coeff_addOutput(l);
					end loop;
--dont need for all cases?
					cntr_to_valid_data <= cntr_to_valid_data + 1;
					if(cntr_to_valid_data = 5+NUM_CYCLES_MULTACCUM) then -- FIXED TO ENSURE PROPER FLUSH  was 6 (worse?)
						evalState <= accumRemainingData_PTB;
						cntr_to_valid_data <= 1;--0;
					end if;
					

				--Sum data remaining in accumulate pipe
				when accumRemainingData_PTB =>
					cntr_to_valid_data <= cntr_to_valid_data + 1;

					case cntr_to_valid_data is
--						when 0 =>
--							for l in 0 to (NUM_CLASS_MAX-2) loop
--								storedSum(l) <= coeff_addOutput(l);    -- 7 already loaded in stored
--							end loop;
						when 1 =>
							for l in 0 to (NUM_CLASS_MAX-2) loop
								accum_inputA(l) <= coeff_addOutput(l); -- 6
							end loop;
						when 2 =>
							for l in 0 to (NUM_CLASS_MAX-2) loop
								storedSum(l) <= coeff_addOutput(l);    -- 5
							end loop;
						when 3 =>
							for l in 0 to (NUM_CLASS_MAX-2) loop
								accum_inputA(l) <= coeff_addOutput(l); -- 4
							end loop;
						when 4 =>
							for l in 0 to (NUM_CLASS_MAX-2) loop
								storedSum(l) <= coeff_addOutput(l);    -- 3
							end loop;
						when 5 =>
							for l in 0 to (NUM_CLASS_MAX-2) loop
								accum_inputA(l) <= coeff_addOutput(l); -- 2
							end loop;
						when 6 =>
							for l in 0 to (NUM_CLASS_MAX-2) loop
								storedSum(l) <= coeff_addOutput(l);    -- 1
							end loop;
						when 7 =>
							for l in 0 to (NUM_CLASS_MAX-2) loop
								accum_inputA(l) <= coeff_addOutput(l); -- 0
							end loop;
						when 8 =>
							NULL;
						when 9 =>
							for l in 0 to (NUM_CLASS_MAX-2) loop
								storedSum(l) <= coeff_addOutput(l); -- 7+6
							end loop;
						when 10 =>
							NULL;
						when 11 =>
							for l in 0 to (NUM_CLASS_MAX-2) loop
								accum_inputA(l) <= coeff_addOutput(l);    -- 5+4
							end loop;
						when 12 =>
							NULL;
						when 13 =>
							for l in 0 to (NUM_CLASS_MAX-2) loop
								storedSum(l) <= coeff_addOutput(l); -- 3+2
							end loop;
						when 14 =>
							NULL;
						when 15 =>
							for l in 0 to (NUM_CLASS_MAX-2) loop
								accum_inputA(l) <= coeff_addOutput(l);    -- 1+0
							end loop;
						when 16 =>
							NULL;
						when 17 =>
							NULL;
						when 18 =>
							NULL;
						when 19 =>
							for l in 0 to (NUM_CLASS_MAX-2) loop
								storedSum(l) <= coeff_addOutput(l);    -- 7+6+5+4
							end loop;
						when 20 =>
							NULL;
						when 21 =>
							NULL;
						when 22 =>
							NULL;
						when 23 =>
							for l in 0 to (NUM_CLASS_MAX-2) loop
								accum_inputA(l) <= coeff_addOutput(l); -- 3+2+1+0
							end loop;
						when 24 =>
							NULL;
						when 25 =>
							NULL;
						when 26 =>
							NULL;
						when 27 =>
							NULL;
						when 28 =>
							NULL;
						when 29 =>
							NULL;
						when 30 =>
							coeff_pipe_enable <= '0'; -- go in 30?
							NULL;
						when 31 =>
							cntr_to_valid_data <= cntr_to_valid_data; -- Dont increment
							
							if(saveRegFull = '0') then
								for l in 0 to (NUM_CLASS_MAX-2) loop
									savedMAC(l) <= coeff_addOutput(l);
								end loop;
								coeffPerSVCpy <= coeffPerSV;
								saveRegFull <= '1';
								if(numClassLeft = 0) then
									--lastStoreFlg <= '1';
									evalState <= idleStateA;
								else
									evalState <= rdNumCoeffInClass;
								end if;
							end if;

						when others =>
							NULL;
					end case;

				when others =>
					coeff_pipe_enable <= '0';
					select_kval_zero <= '0';
					coeffRdIndex <= (others => '0');
					saveRegFull <= '0';
					--lastStoreFlg <= '0';
					evalState <= idleStateA;
			end case;
			
		end if;
	end if;
	end process;	
						
			







	--Seperate out the storage into a seperate task
	storePartialSums: process(class_clock)

	begin

	if(rising_edge(class_clock)) then
		if(class_reset = '1') then
			ps_wren <= '0';
			psumWrIndex <= (others => '0');
			saveRegFullAck <= '0';
			zeroFlg <= '1';
			psumRdIndex <= (others=> '0');
			countState <= zeroValidBits;
		else
			saveRegFullAck <= '0';
			beginValidAdd  <= '0';
			ps_wren <=        '0';
			lastSumFlgIn	<= '0';
		
			case countState is

				when zeroValidBits =>
					zeroFlg <= '0';
					psumDataIn(32) <= '0';
					ps_wren <= '1';

					if(zeroFlg = '1') then
						zeroFlg <= '0';
					else
					
						psumWrIndex <= psumWrIndex+1;
						if((psumWrIndex = 0) OR (psumWrIndex = numPsumRamWords)) then
							psumWrIndex <= (others=> '0');
							ps_wren <= '0';
							countState <= initState;
						end if;
					end if;

				when initState =>
					if(initiateFinalSum = '1') then
						leftCount   <= 1;
						rightCount  <= 2;
						targetCount <= int(svmNumClass);
						countState  <= idleState;
						psumWrIndex <= vec( calcPsumIndex(1,2,NUM_CLASS_MAX) ,psumWrIndex'length);
						psumRdIndex <= vec( calcPsumIndex(1,2,NUM_CLASS_MAX) ,psumRdIndex'length);
					end if;
			
				when idleState =>
					if(saveRegFull = '1') then
						cindex  <= 0;
						countState <= storeClassCompareData;
					end if;

				when storeClassCompareData=>

					-- If valid data already exists in the location to be written to
					if(partialSumOutput(32) = '1') then
						--Move the stored data into the adder
						finalAddInputA <= partialSumOutput(31 downto 0);
						--Move the current coefficient sum to the other adder input
						finalAddInputB <= savedMAC(cindex);
						--Set the adder pipe valid bit
						beginValidAdd <= '1';

						--Clear the RAM valid bit
						psumDataIn(32) <= '0';
						ps_wren <= '1';

						--Load Comparison into Shift Registers
						if(leftCount < rightCount)then
							lowCompareStart  <= leftCount;
							highCompareStart <= rightCount;
						else
							lowCompareStart  <= rightCount;
							highCompareStart <= leftCount;
						end if;

						--Load the last sum bit when done
						if((leftCount = targetCount) AND (rightCount = (targetCount-1))) then
							lastSumFlgIn <= '1';
						end if;						
					else
						--Store off the data to RAM and set the valid flag
						psumDataIn <= '1' & savedMAC(cindex);
						ps_wren <= '1';
					end if;


					--Update Comparisons For next Time Regardless
					if((leftCount <= targetCount) AND (rightCount < targetCount)) then
						if((rightCount+1) /= leftCount) then
							rightCount <= rightCount + 1;
						elsif( ((rightCount+1)=targetCount) AND (leftCount = targetCount)) then
							NULL;
						else
							rightCount <= rightCount + 2;
						end if;
					elsif((leftCount < targetCount) AND (rightCount = targetCount)) then
						leftCount  <= leftCount + 1;
						rightCount <= 1;
					end if;


					countState <= waitForPsumWriteComplete;

				when waitForPsumWriteComplete =>
					psumWrIndex <= vec( calcPsumIndex(leftCount,rightCount,NUM_CLASS_MAX), psumWrIndex'length);
					psumRdIndex <= vec( calcPsumIndex(leftCount,rightCount,NUM_CLASS_MAX) ,psumRdIndex'length);
					if(cindex = (coeffPerSVCpy-1)) then
						saveRegFullAck <= '1';
						countState <= waitRegFullZero;
					else 
						countState <= storeClassCompareData;
					end if;
					
					--Increment cindex
					cindex  <= cindex+1;
					
				when waitRegFullZero =>
					if(saveRegFull = '0') then
						if((leftCount = targetCount) AND (rightCount >= (targetCount-1))) then
							countState <= initState;
						else
							countState <= idleState;
						end if;
					end if;
					
				when others =>
					ps_wren <= '0';
					psumWrIndex <= (others => '0');
					saveRegFullAck <= '0';
					zeroFlg <= '1';
					psumRdIndex <= (others=> '0');
					countState <= zeroValidBits;
			end case;
		end if;
	end if;
	end process;

	

	--7 c.c delay
	FinalAddUnit: addSubFP32 PORT MAP (
		aclr	 	=> class_reset,
		add_sub         => '1',
		clk_en          => '1',--fsum_clk_en,
		clock	 	=> class_clock,
		dataa	 	=> finalAddInputA,
		datab	 	=> finalAddInputB,
		result	=> sumOut
	);
	-- 1 c.c. delay
	FinalCompareUnit : fp32_compare_gt PORT MAP (
		aclr	 => class_reset,
		clk_en   => '1',
		clock	 => class_clock,
		dataa	 => sumOut,
		datab	 => X"00000000",
		agb	 => compare_out
	);	
		

		


		
	------------------------------------------------------------------------------	
	-- Used to help detect when comparisons are valid
	-- This is essentially a shift register that gets loaded at the start of
	-- the pipeline
	------------------------------------------------------------------------------
	shiftSummationResultsProcess: process(class_clock)
	begin
	if(rising_edge(class_clock)) then
		if(class_reset = '1') then
			validShftReg  		<= (others => '0');
			lastSumShftReg		<= (others => '0');
		else
			validShftReg  		<= beginValidAdd    & validShftReg(FINAL_COMPARE_STAGES downto 1);
			lastSumShftReg		<= lastSumFlgIn	    & lastSumShftReg(FINAL_COMPARE_STAGES downto 1);

			lowCompareShftReg(FINAL_COMPARE_STAGES)   <=lowCompareStart;
			upperCompareShftReg(FINAL_COMPARE_STAGES) <= highCompareStart;
			for l in FINAL_COMPARE_STAGES downto 1 loop
				lowCompareShftReg(l-1)  	<= lowCompareShftReg(l);		--Integer Arrays
				upperCompareShftReg(l-1)  	<= upperCompareShftReg(l);
			end loop;
		end if;
	end if;
	end process;		
	


	
	--------------------------------------------------------------------------
	-- Final Voting Calculations                                            --
	-- This process starts when beginVote is set high.                      --
	-- Take the final comparison (when valid) and increment the votes for   --
	-- the corresponding class.                                             --
        -- Comparisons occur in the following order for 7 classes:              --
        --    1v2, 1v3, 1v4, 1v5, 1v6, 1v7,                                     --
	--    2v3, 2v4, 2v5, 2v6, 2v7                                           --
	--    3v4, 3v5, 3v6, 3v7                                                --
	--    4v5, 4v6, 4v7                                                     --
	--    5v6, 5v7                                                          --
        --    6v7                                                               --
        -- The floating point unit compares for > 0 (=True).  If > 0, vote for  --
        -- lower class, otherwise vote for the higher class being compared.     --
	-- Max votes = 6 for 7 classes                                          --
	-- Note: The same order is followed for less/more than 7 classes, but   --
	-- with the non-applicable comparisons being removed/added.             --
	--                                                                      --
	-- When complete, the process outputs the elected class	and sets        --
	-- classEvalComplete active high.                                       --
	--------------------------------------------------------------------------
	voteCtrl: process(class_clock)
	begin

	if(rising_edge(class_clock)) then
		if(class_reset = '1') then
			classEvalComplete <= '0';
			classOut <= (others => '0');
			voteState <= waitForRestart_Pulse0;
		else
			case voteState is
			
				when waitForRestart_Pulse0 =>
					if(class_restart = '0') then
						voteState <= waitForRestart_Pulse1;
					end if;
					classEvalComplete <= '0';   -- Clear valid class bit when restart initiated
					
				when waitForRestart_Pulse1 =>
					if(class_restart = '1') then
						electedClass <= 1;
						maxVotes <= (others => '0');
						classOut <= (others => '0');

						for i in 1 to NUM_CLASS_MAX loop
						    voteCnt(i) <= (others => '0');
						end loop;
						voteState <= waitForValidCompare;
					end if;

				when waitForValidCompare =>
					if(compare_valid = '1') then
						if(compare_out = '1') then
							voteCnt(cmpLowOut) <= voteCnt(cmpLowOut) + 1;
							-- Update max votes and elected class
							if(voteCnt(cmpLowOut)+1 > maxVotes) then
								electedClass <= cmpLowOut;
								maxVotes <= voteCnt(cmpLowOut)+1;
							elsif ( (cmpLowOut < electedClass) AND (voteCnt(cmpLowOut)+1 = maxVotes) ) then
								electedClass <= cmpLowOut;
							end if;
						else
							voteCnt(cmpHighOut) <= voteCnt(cmpHighOut) + 1;
							-- Update max votes and elected class
							if(voteCnt(cmpHighOut)+1 > maxVotes) then
								electedClass <= cmpHighOut;
								maxVotes <= voteCnt(cmpHighOut)+1;
							elsif( (cmpHighOut < electedClass) AND (voteCnt(cmpHighOut)+1 = maxVotes) ) then
								electedClass <= cmpHighOut;
							end if;
						end if;

						if(lastSumFlgOut = '1') then
							voteState <= outputResult;
						end if;
					end if;					

				when outputResult =>
					classEvalComplete <= '1';
					classOut <= std_logic_vector(to_unsigned(electedClass, classOut'length));
					voteState <= waitForRestart_Pulse0;
					
				when others =>
					classEvalComplete <= '0';
					classOut <= (others => '0');
					voteState <= waitForRestart_Pulse0;
			end case;
		end if;
	end if;
	end process;		

	
	--------------------------------------------------------------------------------
	-- This process loads the local memories with new SVM Rho and Coefficient Data--
	-- This takes place at initialization, prior to Running SVM Real-time         --
	-- This is NOT time critical.                                                 --
	--                                                                            --
	-- The process expects coeff_rho_WrStateRst to first be pulsed.               --
	-- This will begin write operations.  It then expects the higher level module --
	-- module to present data on the coef/rho shared databus and that the module  --
	-- will set the dvalid signal.  The process will then write the data and set  --
	-- dack high.  The higher level module will then clear dvalid and on the next --
	-- clock cycle, this process will clear dack.  The higher level module will   --
   -- present new data once dack is clear again.                                 --
	--                                                                            --
	-- Data is expected to be sent starting with the Rho values:                  --
   -- NUM_MODELS*((NUM_CLASS_MAX)*(NUM_CLASS_MAX-1)/2) Rho Values should be      --
   -- written.                                                                   --
	-- After sending all Rho values, the term signal is pulsed, signifying that   --
	-- coefficient writes are to begin.  yi*alpha coefficients are then written   --
	-- until the term signal is pulsed again.  At this time, the process reenters --
	-- the idle state.  Note that any header/informational data is copied across  --
   -- all coefficient rams to relieve indexing complexity during run-time.       --
	--------------------------------------------------------------------------------
	coeffAndRho_write_ctrl: process(coeff_rho_clock)
	begin
	if(rising_edge(coeff_rho_clock)) then
		if(class_reset = '1') then
			coeffWrIndex 	<= (others => '0');
			rhoWrIndex 	<= (others => '0');
			rhoRAM_wren	<= '0';
			coeffRAM_Wren   <= (others => '0');
			coeff_rho_dack  <= '0';
			wrState 	<= wrIdleState;
			c_ram_select    <= 0;
		else
		
			case wrState is

				when wrIdleState =>
					if(coeff_rho_WrStateRst = '1') then
						coeffWrIndex 	<= (others => '0');
						rhoWrIndex 	<= (others => '0');
						c_ram_select <= 0;
						initNumCoefRam_Flg <= '1';
						wrState <= waitForEndResetPulse;
					end if;			

				when waitForEndResetPulse =>
					if(coeff_rho_WrStateRst = '0') then
						wrState <= wait_For_Rho_Dvalid_Or_Term;
					end if;
			
				when wait_For_Rho_Dvalid_Or_Term =>
					if(coeff_rho_dvalid = '1') then
						rhoRAM_wren <= '1';
						wrState <= writeRhoValue;
					elsif(coeff_rho_termSig = '1') then
						coeff_rho_dack <= '1';
						wrState <= wait_For_Term_Low_1;
					end if;

				when writeRhoValue =>
					rhoWrIndex <= rhoWrIndex + 1;
					rhoRAM_wren <= '0';
					coeff_rho_dack <= '1';
					wrState <= rho_wait_for_dvalid_low;

				when rho_wait_for_dvalid_low =>
					if(coeff_rho_dvalid = '0') then
						coeff_rho_dack <= '0';
						wrState <= wait_For_Rho_Dvalid_Or_Term;
					end if;
					
				when wait_For_Term_Low_1 =>
					if(coeff_rho_termSig = '0') then
						coeff_rho_dack <= '0';
						wrState <= wait_For_Coeff_Dvalid_Or_Term;
					end if;
					
				when wait_For_Coeff_Dvalid_Or_Term =>
					if(coeff_rho_dvalid = '1') then
						coeffRAM_wren(c_ram_select) <= '1';
						if(initNumCoefRam_Flg = '1') then
							numCoefRam <= int(coeffAndRhoDataBus) - 2;
							initNumCoefRam_Flg <= '0';
						end if;
						wrState <= writeCoeffValue;
					elsif(coeff_rho_termSig = '1') then
						coeff_rho_dack <= '1';
						wrState <= wait_For_Term_Low_2;
					end if;

				when writeCoeffValue =>
					coeffRAM_wren(c_ram_select) <= '0';
					coeff_rho_dack <= '1';
					
					--Adjust next RAM/index to be written to
					--Fix coefficient writing for informational tagged data
               if( (c_ram_select = numCoefRam) OR
					    (forceCoeffIndexIncr = '1') ) then
						c_ram_select <= 0;
						coeffWrIndex <= coeffWrIndex + 1;
					else
						c_ram_select <= c_ram_select + 1;
					end if;
					wrState <= ceoff_wait_for_dvalid_low;

				when ceoff_wait_for_dvalid_low =>
					if(coeff_rho_dvalid = '0') then
						coeff_rho_dack <= '0';
						wrState <= wait_For_Coeff_Dvalid_Or_Term;
					end if;

				when wait_For_Term_Low_2 =>
					if(coeff_rho_termSig = '0') then
						coeff_rho_dack <= '0';
						wrState <= wrIdleState;
					end if;
						
				when others =>
					coeffWrIndex 	<= (others => '0');
					rhoWrIndex 	<= (others => '0');
					rhoRAM_wren	<= '0';
					coeffRAM_Wren   <= (others => '0');
					coeff_rho_dack  <= '0';
					wrState 	<= wrIdleState;
					c_ram_select    <= 0;
					end case;
		end if;
	end if;
	end process;
		
end architecture;

