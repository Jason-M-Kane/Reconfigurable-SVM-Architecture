-------------------------------------------------------------------------------
-- Jason Kane
--
-- SVM TOP Level Test Module
--
-- Input:  
-- Output: 
--
-------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
USE IEEE.std_logic_unsigned.all;
use IEEE.NUMERIC_STD.ALL;
use work.limb_feature_pkg.all;
use work.z48common.all;
use work.fp_components.all;




entity svm_top_test is
	Port (
				cpu_resetn				: in std_logic;
				clkin_50					: in std_logic;
				
				hsma_d1_uart_rx		: out std_logic;		-- UART RX, FPGA TX  hsma_d(1)  Pin 42 on J1, 2.5V I/O, AK29.  Pin 4 on header.
				hsma_d3_uart_tx		: in std_logic  		-- UART TX, FPGA RX  hsma_d(3)  Pin 44 on J1, 2.5V I/O, AP28.  Pin 6 on header.
			);
end svm_top_test;




	
ARCHITECTURE Behavioral of SVM_TOP_TEST is

	type timingState_TYPE is (waitForRTDataLow,waitForRTDataHigh,COUNT_TICKS_50MHZ,
		waitforTxAck, waitForDackLow);
		
	type assignStateTYPE is (waitForDvalid, waitForDvalidLow);


	
	component pll_mod is
	port (
		refclk   : in  std_logic; 			--  refclk.clk
		rst      : in  std_logic; 			--   reset.reset
		outclk_0 : out std_logic;        -- outclk0.clk
		locked   : out std_logic         --  locked.export
	);
	end component;
	
	
	alias fpga_rx	: std_logic is hsma_d3_uart_tx;
	alias fpga_tx	: std_logic is hsma_d1_uart_rx;


	attribute keep: boolean;
	
-- Letter
	constant NUM_FEATURES 			: integer := 16;
	constant NUM_CLASS_MAX			: integer := 26;
	constant NUM_MODELS   			: integer := 1;--4;
	constant TOTAL_NUM_SV 			: integer := 15000;
	constant MAX_SV_IN_LRG_MODEL	: integer := 14610;
	
-- Baseline	
--	constant NUM_FEATURES 			: integer := 46;
--	constant NUM_CLASS_MAX			: integer := 7;
--	constant NUM_MODELS   			: integer := 4; 
--	constant TOTAL_NUM_SV 			: integer := 600;
--	constant MAX_SV_IN_LRG_MODEL	: integer := 200;

	
	-- PLL Clock Signals
	signal pll_clock_25			: std_logic;
	signal pll_lock				: std_logic;
	signal pll_derived_reset	: std_logic := '1';
	signal arst                : std_logic;
	signal grst                : std_logic;
	signal grst_shift          : std_logic_vector(2 downto 0);
	
	-- SVM Signals
	signal featureExtractComplete	: std_logic;
	signal model_selected			: integer range 0 to (NUM_MODELS-1);
	signal svm_maj_prediction		: std_logic_vector(15 downto 0);
	signal SVM_COMPLETE				: std_logic;
	
	
	-- Write RAM signals
	signal svmModelDataBus 			: std_logic_vector(31 downto 0);
	signal svmModelWrStateRst		: std_logic;  	-- Restart RAM Write state machine when '1'
	signal kernel_termSig			: std_logic;
	signal kernel_dvalid				: std_logic;
	signal kernel_dack				: std_logic;				
	signal coeff_rho_termSig		: std_logic;
	signal coeff_rho_dvalid			: std_logic;
	signal coeff_rho_dack			: std_logic;
	signal forceCoeffIndexIncr		: std_logic;

	--Kernel Parameter Signals
	signal kernel_select : std_logic_vector(1 downto 0);
	signal kernelp_gamma:  std_logic_vector(31 downto 0);
	signal kernelp_a:  std_logic_vector(31 downto 0);
	signal kernelp_r:  std_logic_vector(31 downto 0);
	signal kernelp_d:  std_logic_vector(31 downto 0);
	signal kernelp_d_oddflg: std_logic;
	signal kernel_param_valid : std_logic;
	
	
	-- These signals currently dont go anywhere.  They go to the feature extraction unit
	signal feature_RT_BUS32	: std_logic_vector(31 downto 0);	-- SVM Testing
	signal feature_RT_dvalid	: std_logic;

	
	signal inputFeatures : floatArray(0 to (NUM_FEATURES-1));	

	
	-- Timing and response signals
	signal processingTime 		: std_logic_vector(31 downto 0);
	signal tx_uart_data_valid	: std_logic;
	signal tx_dack					: std_logic;
	signal timingState			: timingState_TYPE;

	
	signal assignState : assignStateTYPE;

	-- KEEP
--	attribute keep of featureExtractComplete: signal is true;
--	attribute keep of inputFeatures: signal is true;
--	attribute keep of assignState: signal is true;
--	attribute keep of tx_uart_data_valid: signal is true;
--	attribute keep of SVM_COMPLETE: signal is true;

BEGIN


	
	-- PLL Module
	pll: pll_mod PORT MAP (
				refclk   => clkin_50, 			--  refclk.clk
				rst      => not cpu_resetn, 		--   reset.reset
				outclk_0 => pll_clock_25,        -- outclk0.clk
				locked =>   pll_lock
			);
					
		
	
	-- Module Determines Load Cell Features
	SVM_MODULE : entity WORK.svm_top(Behavioral)
		generic map(
			NUM_FEATURES => NUM_FEATURES,
			NUM_CLASS_MAX =>NUM_CLASS_MAX, --         : integer;  -- Maximum Number of Classes the Hardware Will Handle ; WAS Fixed at 7
			NUM_MODELS  => NUM_MODELS,    --        : integer;  -- Number of simultaneous models to support
			TOTAL_NUM_SV =>TOTAL_NUM_SV,    --        : integer;  -- Maximum # of SV vectors to be stored (for all models)
			MAX_SV_IN_LRG_MODEL =>MAX_SV_IN_LRG_MODEL
		)
		port map ( 
				--Clock and Reset
				pll_clock_25,			-- 			: in  STD_LOGIC;
				grst,						-- 			: in  STD_LOGIC;
								
				--SVM Feature Vector Input
				featureExtractComplete,--			: in std_logic;
				model_selected,--							: in std_logic_vector(3 downto 0);
				inputFeatures ,--						: in emgFeatureArray;

				-- SVM Kernel Selection
				kernel_select, 		--: in std_logic_vector(1 downto 0);
				kernelp_gamma, 		--: in std_logic_vector(31 downto 0);
				kernelp_a, 		--: in std_logic_vector(31 downto 0);
				kernelp_r, 		--: in std_logic_vector(31 downto 0);
				kernelp_d, 		--: in std_logic_vector(31 downto 0);
				kernelp_d_oddflg,
				kernel_param_valid, 	--: in std_logic;

				--UART Model Data Signaling
				svmModelDataBus,--					: in std_logic_vector(31 downto 0);
				svmModelWrStateRst,--				: in std_logic;  	-- Restart RAM Write state machine when '1'
				pll_clock_25,--						: in std_logic;   -- Write clock for 46 RAMs
				kernel_termSig,--						: in std_logic;
				kernel_dvalid,--						: in std_logic;
				kernel_dack,--							: out std_logic;				
				coeff_rho_termSig,--					: in std_logic;
				coeff_rho_dvalid,--					: in std_logic;
				coeff_rho_dack,--						: out std_logic;
				forceCoeffIndexIncr,
				
				--SVM Feedback
				svm_maj_prediction,		--				: out std_logic_vector(2 downto 0);	-- Class 1 to 7, 0 invalid
				SVM_COMPLETE				--		: out std_logic							-- '1' = TRUE			-- '1' = TRUE
			);
			


			
	-- UART MODULE
	UART_MODULE	: entity work.uart_comms_top(behavioral)
		generic map(
			NUM_CLASS_MAX =>NUM_CLASS_MAX, --         : integer;  -- Maximum Number of Classes the Hardware Will Handle ; WAS Fixed at 7
			NUM_MODELS  =>NUM_MODELS,    --        : integer;  -- Number of simultaneous models to support
			NUM_FEATURES => NUM_FEATURES
		)
		port map (
			grst, 			--RESET							:	IN std_logic;		-- Master Reset
			pll_clock_25, 	--CLOCK							:	IN std_logic;		-- UART Clock
			fpga_rx,		-- uart_rxd						:	in std_logic;		-- Physical UART RX pin
			fpga_tx,		--uart_txd						:	out std_logic;		-- Physical UART TX pin
			
			-- Comms to real-time 16-bit databus
			feature_RT_BUS32,
			feature_RT_dvalid,	--RT_rx_dvalid				: out std_logic;

			-- Kernel Parameters
			kernel_select, 		--: out std_logic_vector(1 downto 0);
			kernelp_gamma, 		--: out std_logic_vector(31 downto 0);
			kernelp_a, 		--: out std_logic_vector(31 downto 0);
			kernelp_r, 		--: out std_logic_vector(31 downto 0);
			kernelp_d, 		--: out std_logic_vector(31 downto 0);
			kernelp_d_oddflg,
			kernel_param_valid,
			model_selected,
			
			------------------------------------------------
			-- Comms to internal module RAM write databus --
			------------------------------------------------
			svmModelWrStateRst,	 --		: out std_logic;  	-- Restart RAM Write state machines when '1'
			svmModelDataBus, 			--	: out std_logic_vector(31 downto 0);

			-- Model and Coefficient/Rho RAM write signaling (SVM Related)
			kernel_termSig,			--: out std_logic;
			kernel_dvalid,				--	: out std_logic;
			kernel_dack	,				--: in std_logic;
			coeff_rho_termSig,		--	: out std_logic;
			coeff_rho_dvalid,			--: out std_logic;
			coeff_rho_dack,			--: in std_logic;
			forceCoeffIndexIncr,	--
			
			-- UART Reply Data
			svm_maj_prediction(7 downto 0),	--uart_TX_Class_Predict	: in std_logic_vector(7 downto 0);
			processingTime,						-- uart_TX_Time				: in std_logic_vector(31 downto 0);
			tx_uart_data_valid,		--: in std_logic;
			tx_dack						--: out std_logic;
		);
		


		
		
		
	-- SVM Timing/Completion Reporting Process
	process(grst, pll_clock_25) is
   begin
      if(grst = '1') then
         tx_uart_data_valid <= '0';
			timingState <= waitForRTDataLow;
      elsif(rising_edge(pll_clock_25)) then
			CASE timingState IS
				WHEN waitForRTDataLow =>
					if(featureExtractComplete = '0') then
						timingState <= waitForRTDataHigh;
					end if;
					
				WHEN waitForRTDataHigh =>
					if(featureExtractComplete = '1') then
						processingTime <= (others => '0');
						timingState <= COUNT_TICKS_50MHZ;
					end if;

				WHEN COUNT_TICKS_50MHZ =>
					if(SVM_COMPLETE = '1') then
						tx_uart_data_valid <= '1';
						timingState <= waitforTxAck;
					else
						processingTime <= processingTime + 1;
					end if;
					
				WHEN waitforTxAck =>
					if(tx_dack = '1') then
						tx_uart_data_valid <= '0';
						timingState <= waitForDackLow;
					end if;
				
				WHEN waitForDackLow =>
					if(tx_dack = '0') then
						timingState <= waitForRTDataLow;
					end if;
				WHEN others =>
					tx_uart_data_valid <= '0';
					timingState <= waitForRTDataLow;
			END CASE;
      end if;
   end process;

		
			
	--PLL Derived RESET Process
	-- pll_derived_reset
	arst <= (not cpu_resetn) or (not pll_lock);
   process(arst, clkin_50) is
      variable rstcount: std_logic_vector(19 downto 0);
   begin
      if(arst = '1') then
         pll_derived_reset <= '1';
         rstcount := (others => '0');
      elsif(rising_edge(clkin_50)) then
         if(rstcount = (rstcount'range => '1')) then
            pll_derived_reset <= '0';
			else
				rstcount := rstcount + 1;
         end if;
      end if;
   end process;
	
	
	
	process(pll_clock_25) is begin
		if(rising_edge(pll_clock_25)) then
			grst_shift <= grst_shift(grst_shift'high - 1 downto grst_shift'low) & pll_derived_reset;
		end if;
	end process;
	grst <= grst_shift(grst_shift'high);
	
	

	
	-- Assigns incoming Feature Vectors and Phase to registers, for testing	
	assignFeatVect: process(pll_clock_25)
	variable mycount : integer := 0;
	begin

	if(rising_edge(pll_clock_25)) then
		if(grst = '1') then
			mycount := 0;
			featureExtractComplete <= '0';
			assignState <= waitForDvalid;
		else
			featureExtractComplete <= '0';
			
			case assignState is
			
				when waitForDvalid =>
					if(feature_RT_dvalid = '1') then
						
						-- Assign incoming value to the correct register
						inputFeatures(mycount) <= feature_RT_BUS32;
						mycount:= mycount + 1;
						if(mycount = (NUM_FEATURES)) then
							featureExtractComplete <= '1';
							mycount := 0;
						end if;
						assignState <= waitForDvalidLow;
					end if;
					
				when waitForDvalidLow =>
					if(feature_RT_dvalid = '0') then
						assignState <= waitForDvalid;
					end if;
					
				when others =>
					mycount := 0;
					featureExtractComplete <= '0';
					assignState <= waitForDvalid;
			end case;
		end if;
	end if;

	end process;	
	

END ARCHITECTURE Behavioral;






	
	
	
	
