-------------------------------------------------------------------------------
-- Jason Kane
--
-- Kernel Evaluation
--
-- Input:  
-- Output: 
--
-------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
USE IEEE.std_logic_unsigned.all;
use IEEE.NUMERIC_STD.ALL;

LIBRARY altera_mf;
USE altera_mf.altera_mf_components.all;

use work.fp_components.all;
use work.z48common.all;



entity multi_kernel is
	generic(
                NUM_FEATURES:        integer;  -- Number of Input Feature Elements
                NUM_MODELS:          integer;  -- Number of simultaneous models to support
                TOTAL_NUM_SV:          integer;  -- Maximum # of SV vectors to be stored (for all models)
                MAX_SV_IN_LRG_MODEL: integer  -- Maximum # of SV vectors to be stored in the largest model
        );
	port(
	
		--Clock and Reset
		k_clock                                 : in  STD_LOGIC;
		k_reset                                 : in  STD_LOGIC;  -- Reset = '1', Not in Reset = '0'
		k_restart                               : in  STD_LOGIC;  -- Restart the state machine when pulsed '1'
				
		--Input Feature Vectors
		inputFeatures                           : in floatArray(0 to (NUM_FEATURES-1));

		--Input Kernel Selection Parameters
		kernel_select		: in std_logic_vector(1 downto 0);
		kernelp_gamma		: in std_logic_vector(31 downto 0);
		kernelp_a		: in std_logic_vector(31 downto 0);
		kernelp_r		: in std_logic_vector(31 downto 0);
		kernelp_d		: in std_logic_vector(31 downto 0);
		kernelp_d_oddflg : in std_logic;
		kernel_param_valid	: in std_logic;
		
		--Input SVM Model Databus (Currently restricted to 4 models)
		svmModelDataBus                         : in std_logic_vector(31 downto 0);
		svmModelWrStateRst                      : in std_logic;   -- Restart RAM Write state machine when '1'
		model_wr_clock                          : in std_logic;   -- Write clock for RAMs
		kernel_termSig                          : in std_logic;   
		kernel_dvalid                           : in std_logic;	
		kernel_dack                             : out std_logic;
		
		--Determines Model to be used
		model_select                            : in integer range 0 to (NUM_MODELS-1);
		
		--Output Interface for Calculated Kernel Values
		kernelCalculationsComplete              : out std_logic;
		kernelRAMRdIndex                        : in std_logic_vector( (log2c(MAX_SV_IN_LRG_MODEL+1)-1) downto 0);  --log2c
		kernelValueOut                          : out std_logic_vector(31 downto 0)
	);
end entity multi_kernel;






architecture mixed of multi_kernel is

	constant LINEAR_KERNEL		: std_logic_vector(1 downto 0) := "00";
	constant POLYNOMIAL_KERNEL	: std_logic_vector(1 downto 0) := "01";
	constant GAUSSIAN_KERNEL	: std_logic_vector(1 downto 0) := "10";
	constant SIGMOID_KERNEL		: std_logic_vector(1 downto 0) := "11";

	constant NUM_STAGES         : integer := log2c(NUM_FEATURES);	-- N, where NUM_FEATURES (rounded to next highest power of 2) = 2^N 
	constant LAST_FEAT_INDEX    : integer := (NUM_FEATURES-1);
	constant NUM_INTERCONNECTS  : integer := determineNumInterconnectSigs(NUM_FEATURES);

	constant NEG_DETECT_STAGES : integer := NUM_LOG_CYCLES + NUM_FPMULT_CYCLES + NUM_EXP_CYCLES;


	constant KERNEL_PIPELINE_STALL_TIME_LIN  : integer := (NUM_FPMULT_CYCLES) + (NUM_STAGES*NUM_FPADD_CYCLES) - 1;

	constant KERNEL_PIPELINE_STALL_TIME_POLY : integer := (NUM_FPMULT_CYCLES) +        -- Multipliers
                                                         (NUM_STAGES*NUM_FPADD_CYCLES) +                 -- Adders
                                                         (NUM_FPMULT_CYCLES + NUM_FPADD_CYCLES + NUM_LOG_CYCLES) +   -- Scaling and Natural Log (Subtract 1 to account for 0 offset)
																			(NUM_FPMULT_CYCLES + NUM_EXP_CYCLES)- 1+2; --2 extra cycles
	constant KERNEL_PIPELINE_STALL_TIME_GAUSSIAN : integer := (NUM_FPSUB_CYCLES + NUM_FPMULT_CYCLES) +        -- Subtractors and Multipliers
																			(NUM_STAGES*NUM_FPADD_CYCLES) +                 -- Adders
                                                         (NUM_FPMULT_CYCLES + NUM_FPADD_CYCLES) +   -- Scaling and Natural Log (Subtract 1 to account for 0 offset)
																			(NUM_FPMULT_CYCLES + NUM_EXP_CYCLES)- 1 + 1; -- 1 extra cycle
	constant KERNEL_PIPELINE_STALL_TIME_SIGMOID  : integer := (NUM_FPMULT_CYCLES) +        -- Multipliers
                                                         (NUM_STAGES*NUM_FPADD_CYCLES) +                 -- Adders
                                                         (NUM_FPMULT_CYCLES + NUM_FPADD_CYCLES) +   -- Scaling and Natural Log (Subtract 1 to account for 0 offset)
																			(NUM_FPMULT_CYCLES + NUM_EXP_CYCLES + NUM_FPADD_CYCLES + NUM_FPDIV_CYCLES)- 1;
																			
	constant dpKernRamHighBit      : integer := log2c(MAX_SV_IN_LRG_MODEL+1) - 1;  -- +1 accounts for needing 1 extra address to detect end
	constant dpModelRamHighBit     : integer := log2c(TOTAL_NUM_SV+1) - 1;           -- +1 accounts for needing 1 extra address to detect end
   attribute keep: boolean;

	type modelAddrArray is array (integer range <>) of std_logic_vector(dpModelRamHighBit downto 0);


	type wrRamState_TYPE is (wrIdleState, waitForEndResetPulse, writeModelValue,
		wait_For_Dvalid_Or_Term, wait_For_Term_Low_End, wait_for_dvalid_low,wait_For_Term_Low);	
	type gausKernelState_TYPE is (idleStateA,idleStateB,runKernelPipeline,writeRemainingPipelineData);
	type kernelSelState_TYPE is(kselect_idle,kselect_valid);
	
	signal numPipelineStallTime	  : integer;
	
	-- Level 0 Signals
	signal supportVectorElement     : floatArray(0 to LAST_FEAT_INDEX);
	signal subOutput_lvl_0          : floatArray(0 to LAST_FEAT_INDEX);
	
	-- Generated Interconnect Signals
	signal interconnect             : floatArray(0 to determineNumInterconnectSigs(NUM_FEATURES) );

	-- Level N Signals
	signal inMuxACtrl : std_logic;
	signal inMuxBCtrl : std_logic;
	signal outMuxACtrl : std_logic;
	signal outMuxBCtrl : std_logic_vector(1 downto 0);
	signal muxInAOut32 : floatArray(0 to LAST_FEAT_INDEX);
	signal muxInBOut32 : floatArray(0 to LAST_FEAT_INDEX);
	signal scaleOutMult         : std_logic_vector(31 downto 0);
	signal scaleOutAdd    : std_logic_vector(31 downto 0);
	signal logOut         : std_logic_vector(31 downto 0);
	signal muxAOut         : std_logic_vector(31 downto 0);
	signal scaleOutputMult2         : std_logic_vector(31 downto 0);
	signal expResult         : std_logic_vector(31 downto 0);
	signal neg1PlusExp         : std_logic_vector(31 downto 0);
	signal pos1PlusExp         : std_logic_vector(31 downto 0);
	signal sigmoidResult         : std_logic_vector(31 downto 0);
	signal kernelValue			: std_logic_vector(31 downto 0);
	signal d_oddflg			: std_logic;
	
	signal signDetect 	: std_logic;
	signal fpAbsOut	   : std_logic_vector(31 downto 0);
	signal polyGaussResult	: std_logic_vector(31 downto 0);
	signal negDetectReg : std_logic_vector((NEG_DETECT_STAGES-1) downto 0);
	alias signDetectOut : std_logic is negDetectReg(0);

	-- Kernel Selection / Parameters
	signal s_param : std_logic_vector(31 downto 0);
	signal r_param : std_logic_vector(31 downto 0);
	signal a_param : std_logic_vector(31 downto 0);
	signal k_select_state : kernelSelState_TYPE;


	-- SVM Model RAM Signals
	-- svmModel address space needs to index all support vectors
	signal wrState          : wrRamState_TYPE;
	signal svmModelRdAddr   : std_logic_vector(dpModelRamHighBit downto 0);
	signal svmModelWrAddr   : std_logic_vector(dpModelRamHighBit downto 0);
	signal svmModelRamWr    : std_logic_vector(0 to LAST_FEAT_INDEX);
	signal ram_select       : integer range 0 to LAST_FEAT_INDEX;
	signal model_num        : integer range 0 to NUM_MODELS;

	signal model_StartAddr  : modelAddrArray(0 to NUM_MODELS);
		
	-- SVM Kernel Pipeline Control Process
	-- Kernel address space only needs to reach max# support vector present in the largest model
	signal cntr_to_valid_data			: integer;-- range 0 to KERNEL_PIPELINE_STALL_TIME;
	signal svmModelRdStop 				: std_logic_vector(dpModelRamHighBit downto 0);
	signal gausKernelState 				: gausKernelState_TYPE;
	signal kernelRAMWrIndex				: std_logic_vector(dpKernRamHighBit downto 0);
	signal kernelRamWren             : std_logic;
	
	attribute keep of inMuxACtrl			: signal is true;
	attribute keep of inMuxBCtrl			: signal is true;
	attribute keep of outMuxACtrl			: signal is true;
	attribute keep of outMuxBCtrl			: signal is true;
	attribute keep of s_param			: signal is true;
	attribute keep of r_param			: signal is true;
	attribute keep of a_param			: signal is true;
	
	attribute keep of inputFeatures			: signal is true;
	attribute keep of supportVectorElement	: signal is true;
	attribute keep of subOutput_lvl_0 		: signal is true;
	attribute keep of model_StartAddr 		: signal is true;
	attribute keep of numPipelineStallTime : signal is true;
	attribute keep of scaleOutMult			: signal is true;
	attribute keep of kernelValue				: signal is true;
	attribute keep of kernelCalculationsComplete	: signal is true;
	
	attribute keep of cntr_to_valid_data   : signal is true;
	attribute keep of svmModelRdStop   		: signal is true;
	attribute keep of kernelRAMWrIndex   	: signal is true;
	attribute keep of kernelRamWren   		: signal is true;
	attribute keep of svmModelRdAddr   		: signal is true;
	attribute keep of model_num   			: signal is true;
	attribute keep of svmModelRamWr   		: signal is true;
	attribute keep of ram_select   			: signal is true;
	attribute keep of svmModelWrAddr   		: signal is true;
	
	attribute keep of scaleOutAdd   			: signal is true;
	attribute keep of muxAOut   				: signal is true;
	attribute keep of scaleOutputMult2   	: signal is true;
	attribute keep of expResult   			: signal is true;
	attribute keep of interconnect			: signal is true;
	
	attribute keep of negDetectReg			: signal is true;
	attribute keep of fpAbsOut			: signal is true;
	attribute keep of signDetect			: signal is true;
	attribute keep of polyGaussResult			: signal is true;
	


begin	

	
	---------------------------------------------------------------------------
	-- Assemble the hardware to perform a FP pipelined Gaussian Kernel Trick --
	---------------------------------------------------------------------------
	norm_unit: for i in 1 to NUM_STAGES generate
	begin

		-- Generate Subtract and Squaring 	
		GEN_SUB_AND_SQ: if(i = 1) generate
		begin
			GEN_SUB_MULT_INST: for j in 0 to (NUM_FEATURES-1) generate
			
			muxUnitInA_2way : entity WORK.mux32_2way(behavioral)
			PORT MAP (
				ctrl		=> inMuxACtrl,
				data1	 	=> inputFeatures(j),
				data2	 	=> subOutput_lvl_0(j),
				result	=> muxInAOut32(j)
			);
			
			muxUnitInB_2way : entity WORK.mux32_2way(behavioral)
			PORT MAP (
				ctrl		=> inMuxBCtrl,
				data1	 	=> supportVectorElement(j),
				data2	 	=> subOutput_lvl_0(j),
				result	=> muxInBOut32(j)
			);
			
			subUnit: addSubFP32 PORT MAP (
				aclr    => k_reset,
				add_sub	=> '0',
				clk_en	=> '1',
				clock   => k_clock,
				dataa   => inputFeatures(j),
				datab   => supportVectorElement(j),
				result	=> subOutput_lvl_0(j)
			);
			

			multUnit: fp32mult PORT MAP (
				aclr            => k_reset,
				clk_en          => '1',
				clock	        => k_clock,
				dataa	        => muxInAOut32(j),
				datab	        => muxInBOut32(j),
				result	        => interconnect(j)
			);

			end generate GEN_SUB_MULT_INST;
		end generate GEN_SUB_AND_SQ;


		--Addition Chain
		GEN_ADD_CHAIN: if(i >= 1) generate
		begin
			GEN_ADD_INST: for j in 0 to (num_adders(i,NUM_FEATURES) - 1) generate
			addUnit: addSubFP32 PORT MAP (
				aclr    => k_reset,
				add_sub	=> '1',
				clk_en	=> '1',
				clock   => k_clock,
				dataa   => interconnect(2*j+find_first_input(i,NUM_FEATURES)),
				datab   => interconnect(2*j+1+find_first_input(i,NUM_FEATURES)),
				result	=> interconnect(j+find_first_output(i,NUM_FEATURES))
			);
			end generate GEN_ADD_INST;
		end generate GEN_ADD_CHAIN;



		-- Generate a delay path if an odd number of features currently exists
		-- The zero-adder can be replaced with a shift register at some point
		GEN_DELAY: if( (i >= 1) and (check_for_shiftreg(i,NUM_FEATURES) = 1) and (i /= NUM_STAGES) ) generate
		begin
			DELAY_INST: addSubFP32 PORT MAP (
				aclr    => k_reset,
				add_sub	=> '1',
				clk_en	=> '1',
				clock   => k_clock,
				dataa   => interconnect(find_first_input((i+1),NUM_FEATURES)-1),
				datab   => X"00000000",
				result	=> interconnect(find_last_output(i,NUM_FEATURES))
			);
		end generate GEN_DELAY;



		-- Follow-on Output Unit
		Final_Sum_And_Logic: if (i = NUM_STAGES) generate
		begin

			multScaleUnit: fp32mult PORT MAP (
				aclr	 	=> k_reset,
				clk_en   => '1',
				clock	 	=> k_clock,
				dataa	 	=> interconnect(find_last_output(i,NUM_FEATURES)),
				datab	 	=> a_param,
				result	=> scaleOutMult
			);

			addScaleUnit: addSubFP32 PORT MAP (
				aclr    => k_reset,
				add_sub	=> '1',
				clk_en	=> '1',
				clock   => k_clock,
				dataa   => scaleOutMult,
				datab   => r_param,
				result	=> scaleOutAdd
			);

			fpAbsAndDetectSignUnit: entity WORK.abs_signDetect(behavioral)
			PORT MAP (
			  clock	    => k_clock,
			  dataIn     => scaleOutAdd,
           dataOut    => fpAbsOut,
			  pwr_odd    => d_oddflg,
           signModify => signDetect
			);

			-- ** 21 Clock Cycle Latency **
			logUnit: fp32log PORT MAP (
				clk_en	=> '1',
				clock	 	=> k_clock,
				data	 	=> fpAbsOut,
				result	=> logOut
			);

			--
			muxUnitOutA_2way : entity WORK.mux32_2way(behavioral)	
			PORT MAP (
				ctrl		=> outMuxACtrl,
				data1	 	=> scaleOutAdd,
				data2	 	=> logOut,
				result	=> muxAOut
			);

			multScaleUnit2: fp32mult PORT MAP (
				aclr	 	=> k_reset,
				clk_en   => '1',
				clock	 	=> k_clock,
				dataa	 	=> muxAOut,
				datab	 	=> s_param,
				result	=> scaleOutputMult2
			);
			
			-- ** 17 Clock Cycle Latency **
			expUnit:  fp32exp PORT MAP (
				clk_en	=> '1',
				clock	 	=> k_clock,
				data	 	=> scaleOutputMult2,
				result	=> expResult
			);
			

			fpNegateUnit: entity WORK.fp_negate(behavioral)
			PORT MAP (
			  clock	    => k_clock,
			  dataIn     => expResult,
           dataOut    => polyGaussResult,
			  negateOpt  => signDetectOut
			);


			addSigMoid_Min1: addSubFP32 PORT MAP (
				aclr    => k_reset,
				add_sub	=> '1',
				clk_en	=> '1',
				clock   => k_clock,
				dataa   => expResult,
				datab   => FP32VAL_NEG_1_0,
				result	=> neg1PlusExp
			);

			addSigMoid_1: addSubFP32 PORT MAP (
				aclr    => k_reset,
				add_sub	=> '1',
				clk_en	=> '1',
				clock   => k_clock,
				dataa   => expResult,
				datab   => FP32VAL_1_0,
				result	=> pos1PlusExp
			);

			divUnit: fp32div PORT MAP (
				clk_en          => '1',
				clock	 	=> k_clock,
				dataa	 	=> neg1PlusExp,
				datab	 	=> pos1PlusExp,
				result	=> sigmoidResult
			);

			muxUnitOutB_3way : entity WORK.mux32_3way(behavioral)
			PORT MAP (
				ctrl		=> outMuxBCtrl,
				data1	 	=> interconnect(find_last_output(i,NUM_FEATURES)),
				data2	 	=> polyGaussResult,
				data3           => sigmoidResult,
				result	=> kernelValue
			);
		end generate Final_Sum_And_Logic;
        end generate norm_unit;




	
	
	
--Instantiating Megafunctions Using the Port and Parameter Definition
--http://quartushelp.altera.com/11.1/mergedProjects/hdl/mega/mega_file_altsynch_ram.htm

        --------------------------------------------
	--          Model RAM
	--------------------------------------------
	-- Format is:
	-- =========================
	-- Model 1 Class 1 SVs[] 
	-- Model 1 Class 2 SVs[] 
	-- ...
	-- Model 1 Class L SVs[]
	-- Model 2 Class 1 SVs[]
	-- Model 2 Class 2 SVs[]
	-- ...
	-- Model 2 Class L SVs[]
	-- ...
	-- Model 4 Class 1 SVs[]
	-- Model 4 Class 2 SVs[]
	-- ...
	-- Model 4 Class L SVs[]
	-- ==========================
	--
	-- Note:  Each Feature Vector Element in one 1xN SV is stored across N 32-bit RAMs.
	---------------------------------------------

   -----------------------------------------------------------------------------------------------------
	-- Generate NUM_FEATURES 32-bit, NUM_SUPPORT_VECTORS deep DPRAMs DCFIFO                                           
	-- Also links up the B inputs of all subtractors in Level 0
	-----------------------------------------------------------------------------------------------------
   SVM_dprams: for i in 0 to (NUM_FEATURES-1) generate
	begin
		GEN_SVM_MODEL_RAM: if ((i >= 0) and (i <= NUM_FEATURES-1)) generate
		begin
			SVMRamUnit: altsyncram
			generic map(
				address_aclr_b => "NONE",
				address_reg_b => "CLOCK1",
				clock_enable_input_a => "BYPASS",
				clock_enable_input_b => "BYPASS",
				clock_enable_output_b => "BYPASS",
				intended_device_family => "Stratix V",
				lpm_type => "altsyncram",
				numwords_a => TOTAL_NUM_SV+1,
				numwords_b => TOTAL_NUM_SV+1,
				operation_mode => "DUAL_PORT",
				outdata_aclr_b => "NONE",
				outdata_reg_b => "UNREGISTERED",
				power_up_uninitialized => "FALSE",
				widthad_a => dpModelRamHighBit+1,
				widthad_b => dpModelRamHighBit+1,
				width_a => 32,
				width_b => 32,
				width_byteena_a => 1
			)
			PORT MAP (
				address_a => svmModelWrAddr,
				clock0 => not model_wr_clock,
				data_a => svmModelDataBus,
				wren_a => svmModelRamWr(i),
				address_b => svmModelRdAddr,
				clock1 => not k_clock,
				q_b => supportVectorElement(i)

--				data            => svmModelDataBus,
--				rdaddress	=> svmModelRdAddr,
--				rdclock		=> not k_clock,
--				wraddress 	=> svmModelWrAddr,
--				wrclock	 	=> not model_wr_clock,
--				wren            => svmModelRamWr(i),
--				q               => subInputB_lvl_0(i)
			);
		end generate GEN_SVM_MODEL_RAM;
	end generate SVM_dprams;


	--------------------------------------------
	--          Kernel RAM (32-bit Entries)
	--------------------------------------------
	-- Format is:
	-- =========================
	-- Kernel Scalar Value 0
	-- Kernel Scalar Value 1
	-- Kernel Scalar Value 2
	-- Kernel Scalar Value 3
	-- ...
	-- Kernel Scalar Value Max
	---------------------------------------------
        -- RAM to store Kernel Calculation Results
        kernelRAMUnit: altsyncram
	generic map(
		address_aclr_b => "NONE",
		address_reg_b => "CLOCK0",
		clock_enable_input_a => "BYPASS",
		clock_enable_input_b => "BYPASS",
		clock_enable_output_b => "BYPASS",
		intended_device_family => "Stratix V",
		lpm_type => "altsyncram",
		numwords_a => MAX_SV_IN_LRG_MODEL+1,
		numwords_b => MAX_SV_IN_LRG_MODEL+1,
		operation_mode => "DUAL_PORT",
		outdata_aclr_b => "NONE",
		outdata_reg_b => "UNREGISTERED",
		power_up_uninitialized => "FALSE",
		read_during_write_mode_mixed_ports => "DONT_CARE",
		widthad_a => dpKernRamHighBit+1,
		widthad_b => dpKernRamHighBit+1,
		width_a => 32,
		width_b => 32,
		width_byteena_a => 1
	)
	port map (
		clock0           => not k_clock,
		data_a            => kernelValue,
		address_b	=> kernelRAMRdIndex,
		address_a	=> kernelRAMWrIndex,
		wren_a            => kernelRamWren,
		q_b               => kernelValueOut
        );





	-----------------------------------------------------------------------------------------------------
	-- This process controls the filling of the entry state of the pipeline                            --
	-- When all vectors have been processed and the result saved to the kernel array,                  --
	-- A signal is sent from the SVM kernel process to the SVM class determination routine to begin    --
	-----------------------------------------------------------------------------------------------------
	kernelPipelineCtrl: process(k_clock)
	begin

	if(rising_edge(k_clock)) then
		if(k_reset = '1') then
			cntr_to_valid_data <= 0;
			svmModelRdAddr <= (others => '0');
			gausKernelState <= idleStateA;
			kernelRAMWrIndex <= (others => '0');
			kernelRamWren <= '0';
			kernelCalculationsComplete <= '0';
		else
		
			case gausKernelState is
			
				when idleStateA =>
					if(k_restart = '1') then
						kernelCalculationsComplete <= '0';
						gausKernelState <= idleStateB;
					end if;
					
				when idleStateB =>
					if(k_restart = '0') then
						svmModelRdAddr <= model_StartAddr(model_select);
						svmModelRdStop <= model_StartAddr(model_select+1);
						gausKernelState <= runKernelPipeline;
						kernelRAMWrIndex <= (others => '0');
						cntr_to_valid_data <= 0;
					end if;		


				when runKernelPipeline =>
					
					-- Determine When Kernel Output is Good
					if(cntr_to_valid_data = numPipelineStallTime) then
						kernelCalculationsComplete <= '1'; -- First Kernel Output is written and valid to read from
						kernelRamWren <= '1';
					end if;

					-- Determine when to increment kernel RAM write index
					if(cntr_to_valid_data > numPipelineStallTime) then
						kernelRAMWrIndex <= kernelRAMWrIndex + 1;
					else 
						cntr_to_valid_data <= cntr_to_valid_data + 1;
					end if;
					
					-- Check for the end of valid data being injected to the beginning of the pipe
					if(svmModelRdAddr = svmModelRdStop) then
						cntr_to_valid_data <= 1;
						gausKernelState <= writeRemainingPipelineData;
					else 
						svmModelRdAddr <= svmModelRdAddr + 1;
					end if;
					
				when writeRemainingPipelineData =>
					if(cntr_to_valid_data = numPipelineStallTime) then
						kernelRamWren <= '0';
						kernelCalculationsComplete <= '0';
						gausKernelState <= idleStateA;
					else
						cntr_to_valid_data <= cntr_to_valid_data + 1;
					end if;
					kernelRAMWrIndex <= kernelRAMWrIndex + 1;
						
					
				when others =>
					cntr_to_valid_data <= 0;
					svmModelRdAddr <= (others => '0');
					gausKernelState <= idleStateA;
					kernelRAMWrIndex <= (others => '0');
					kernelRamWren <= '0';
					kernelCalculationsComplete <= '0';
			end case;
			
		end if;
	end if;
	end process;

	
	negDetectProcess: process(k_clock)
	begin
	if(rising_edge(k_clock)) then
		if(k_reset = '1') then
			negDetectReg  <= (others => '0');
		else
			negDetectReg <= signDetect & negDetectReg((NEG_DETECT_STAGES-1) downto 1);
		end if;
	end if;
	end process;



	--------------------------------------------------------------------------------
	-- This process switches both the input and output kernel block selections.   --
	-- Four kernels are supported: Linear, Polynomial, Sigmoid, and Gaussian.     --
	--------------------------------------------------------------------------------
	kernelSelect: process(k_clock)
	begin

	if(rising_edge(k_clock)) then
		if(k_reset = '1') then
			k_select_state <= kselect_idle;
		else
		
			case k_select_state is
			
				when kselect_idle =>
					if(kernel_param_valid = '0') then
						k_select_state <= kselect_valid;
					end if;
					
				when kselect_valid =>
					if(kernel_param_valid = '1') then
						d_oddflg <= '0';
						if(kernel_select = LINEAR_KERNEL) then
							s_param <= FP32VAL_1_0;
							r_param <= FP32VAL_0_0;
							a_param <= FP32VAL_1_0;
							inMuxACtrl <= '1';
							inMuxBCtrl <= '1';
							outMuxACtrl <= '0';
							outMuxBCtrl <= "10";
							d_oddflg <= '1';
							numPipelineStallTime <= KERNEL_PIPELINE_STALL_TIME_LIN;
						elsif(kernel_select = POLYNOMIAL_KERNEL) then
							s_param <= kernelp_d;
							r_param <= kernelp_r;
							a_param <= kernelp_a;
							inMuxACtrl <= '1';
							inMuxBCtrl <= '1';
							outMuxACtrl <= '0';
							outMuxBCtrl <= "01";
							d_oddflg <= kernelp_d_oddflg; 
							numPipelineStallTime <= KERNEL_PIPELINE_STALL_TIME_POLY;
						elsif(kernel_select = GAUSSIAN_KERNEL) then
							s_param <= kernelp_gamma;
							r_param <= FP32VAL_0_0;
							a_param <= FP32VAL_1_0;
							inMuxACtrl <= '0';
							inMuxBCtrl <= '0';
							outMuxACtrl <= '1';
							outMuxBCtrl <= "01";
							numPipelineStallTime <= KERNEL_PIPELINE_STALL_TIME_GAUSSIAN;
						else
							--SIGMOID_KERNEL
							s_param <= FP32VAL_2_0;
							r_param <= kernelp_r;
							a_param <= kernelp_a;
							inMuxACtrl <= '1';
							inMuxBCtrl <= '1';
							outMuxACtrl <= '1';
							outMuxBCtrl <= "00";
							numPipelineStallTime <= KERNEL_PIPELINE_STALL_TIME_SIGMOID;
						end if;
						k_select_state <= kselect_idle;
					end if;

				when others =>
					k_select_state <= kselect_idle;
			end case;
		end if;
	end if;
	end process;


	

	--------------------------------------------------------------------------------
	-- This process loads the local memories with new model data                  --
	-- This takes place at initialization, prior to Running SVM Real-time         --
	-- This is NOT time critical.                                                 --
	--                                                                            --
	-- The process expects kernel_termSig to first be set.                        --
	-- This will latch the location of the first model.  This will be acked by    --
	-- setting the kernel dack signal high.  The higher level module then sets    --
	-- dvalid low again, and this module will set dack low again, allowing for    --
	-- the first models data to be sent continuously, using only the dvalid and   --
	-- dack signals in the same handshake manner.                                 --
	-- It then expects that the first model's first SV element (0) will be put on --
	-- the svmModelDataBus and elements 1 through LAST will follow.               --
	-- Then the next SV will be sent in order likewise and so on.                 --
	-- When the 1st model is finished, the kernel_termSig line handshake will     --
	-- reoccur again so that the start of the next model may be latched.  Finally,--
	-- When the last model has been sent, the terminate handshake will occur with --
        -- a final time with the value 0xDEAD on the lower 15 bits.                   --
	-- This state machine will cease until svmModelWrStateRst or k_reset are      --
        -- asserted.                                                                  --
	--------------------------------------------------------------------------------		
	modelRAM_write_ctrl: process(model_wr_clock)
	begin
	if(rising_edge(model_wr_clock)) then
		if(k_reset = '1') then
			svmModelRamWr    <= (others => '0');
			model_num <= 0;
			ram_select <= 0;
			kernel_dack  <= '0';
			wrState 	<= wrIdleState;
		else
		
			case wrState is

				when wrIdleState =>
					if(svmModelWrStateRst = '1') then
						svmModelWrAddr   <= (others => '0');
						model_num <= 0;
						ram_select <= 0;
						wrState <= waitForEndResetPulse;
					end if;			

				when waitForEndResetPulse =>
					if(svmModelWrStateRst = '0') then
						wrState <= wait_For_Dvalid_Or_Term;
					end if;
			
				when wait_For_Dvalid_Or_Term =>
					if(kernel_dvalid = '1') then
						svmModelRamWr(ram_select) <= '1';
						wrState <= writeModelValue;
					elsif(kernel_termSig = '1') then
						model_StartAddr(model_num) <= svmModelWrAddr;
						kernel_dack <= '1';
						if(svmModelDataBus(15 downto 0) = X"DEAD") then
							wrState <= wait_For_Term_Low_End;
						else
							wrState <= wait_For_Term_Low;
							model_num <= model_num + 1;
						end if;
					end if;

				when writeModelValue =>
					svmModelRamWr(ram_select) <= '0';
					if(ram_select = LAST_FEAT_INDEX) then
						ram_select <= 0;
						svmModelWrAddr <= svmModelWrAddr + 1;
					else
						ram_select <= ram_select + 1;
					end if;
					kernel_dack <= '1';
					wrState <= wait_for_dvalid_low;

				when wait_for_dvalid_low =>
					if(kernel_dvalid = '0') then
						kernel_dack <= '0';
						wrState <= wait_For_Dvalid_Or_Term;
					end if;
					
				when wait_For_Term_Low =>
					if(kernel_termSig = '0') then
						kernel_dack <= '0';
						wrState <= wait_For_Dvalid_Or_Term;
					end if;

				when wait_For_Term_Low_End =>
					if(kernel_termSig = '0') then
						kernel_dack <= '0';
						wrState <= wrIdleState;
					end if;
						
				when others =>
					svmModelRamWr   <= (others => '0');
					model_num 	<= 0;
					ram_select 	<= 0;
					kernel_dack  	<= '0';
					wrState 	<= wrIdleState;
					end case;
		end if;
	end if;
	end process;

end architecture;
