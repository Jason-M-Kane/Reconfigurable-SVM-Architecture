-------------------------------------------------------------------------------
-- Jason Kane
--
-- SVM TOP
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
use work.fp_components.all;
use work.z48common.all;


entity SVM_TOP is
	Generic(
		NUM_FEATURES				: integer;
		NUM_CLASS_MAX           : integer;  -- Maximum Number of Classes the Hardware Will Handle ; WAS Fixed at 7
      NUM_MODELS              : integer;  -- Number of simultaneous models to support
		TOTAL_NUM_SV            : integer;  -- Maximum # of SV vectors to be stored (for all models)
		MAX_SV_IN_LRG_MODEL     : integer  -- Maximum # of SV vectors to be stored in the largest model
    );
	Port (
				--Clock and Reset
				svm_clock 		 					: in  STD_LOGIC;
				svm_reset 							: in  STD_LOGIC;
								
				--SVM Feature Vector Input
				featureExtractComplete			: in std_logic;
				model_select						: in integer range 0 to (NUM_MODELS-1);
				inputFeatures    					: in floatArray(0 to (NUM_FEATURES-1));

				-- SVM Kernel Selection
				kernel_select		: in std_logic_vector(1 downto 0);
				kernelp_gamma		: in std_logic_vector(31 downto 0);
				kernelp_a		: in std_logic_vector(31 downto 0);
				kernelp_r		: in std_logic_vector(31 downto 0);
				kernelp_d		: in std_logic_vector(31 downto 0);
				kernelp_d_oddflg : in std_logic;
				kernel_param_valid	: in std_logic;

				--UART Model Data Signaling
				svmModelDataBus					: in std_logic_vector(31 downto 0);
				svmModelWrStateRst				: in std_logic;  	-- Restart RAM Write state machine when '1'
				wr_clock								: in std_logic;   -- Write clock for 46 RAMs
				kernel_termSig						: in std_logic;
				kernel_dvalid						: in std_logic;
				kernel_dack							: out std_logic;				
				coeff_rho_termSig					: in std_logic;
				coeff_rho_dvalid					: in std_logic;
				coeff_rho_dack						: out std_logic;
				forceCoeffIndexIncr					: in std_logic;
				
				--SVM Feedback
				svm_prediction						: out std_logic_vector(15 downto 0);	-- Class 1 to N, starting from 0
				svm_predict_complete				: out std_logic							   -- '1' = TRUE
			);
end SVM_TOP;




	



ARCHITECTURE Behavioral of SVM_TOP is


	attribute keep: boolean;
	
	type checkState_TYPE is(lookForLow, lookForHigh);


	signal kernelCalculationsComplete 	: std_logic;
	signal kernelIndex					 	: std_logic_vector( (log2c(MAX_SV_IN_LRG_MODEL+1)-1) downto 0);
	signal kernelValue					 	: std_logic_vector(31 downto 0);
	signal svm_restart						: std_logic;				

	
	--SVM Restart Process
	signal checkState : checkState_TYPE;
	
	attribute keep of svm_predict_complete	: signal is true;
	attribute keep of svm_prediction	: signal is true;


BEGIN

			
	SVM_KERNEL_MODULE : entity WORK.multi_kernel(mixed)
	generic map(
      NUM_FEATURES => NUM_FEATURES,--:        integer;  -- Number of Input Feature Elements
      NUM_MODELS => NUM_MODELS,--:          integer;  -- Number of simultaneous models to support
      TOTAL_NUM_SV => TOTAL_NUM_SV,--:          integer;  -- Maximum # of SV vectors to be stored (for all models)
		MAX_SV_IN_LRG_MODEL => MAX_SV_IN_LRG_MODEL --: integer  -- Maximum # of SV vectors to be stored in the largest model
   )

	port map(
		--Clock and Reset
		svm_clock,   --k_clock 		 		: in  STD_LOGIC;
		svm_reset,   --k_reset 				: in  STD_LOGIC;  -- Reset = '1', Not in Reset = '0'
		svm_restart, --k_restart			: in  STD_LOGIC;	-- Restart the state machine when pulsed '1'
				
		--Input Feature Vectors
		inputFeatures,--                           : in floatArray(0 to (NUM_FEATURES-1));

		--Input Kernel Parameters
		kernel_select,		--: in std_logic_vector(1 downto 0);
		kernelp_gamma,		--: in std_logic_vector(31 downto 0);
		kernelp_a,		--: in std_logic_vector(31 downto 0);
		kernelp_r,		--: in std_logic_vector(31 downto 0);
		kernelp_d,		--: in std_logic_vector(31 downto 0);
		kernelp_d_oddflg,
		kernel_param_valid,
		
		--Input SVM Model Databus (Currently restricted to 4 models)
		svmModelDataBus,    --svmModelDataBus					: in std_logic_vector(31 downto 0);
		svmModelWrStateRst, --svmModelWrStateRst				: in std_logic;  -- Restart RAM Write state machine when '1'
		wr_clock,       		--svm_wr_clock						: in std_logic;   -- Write clock for 46 RAMs
		kernel_termSig,     --								: in std_logic;
		kernel_dvalid,    	--				: in std_logic;	-- Pulses high to record model 1 -> 4 start addresses
		kernel_dack,
		
		--Determines Model to be used
		model_select, --del_select                            : in std_logic_vector( (log2c(NUM_MODELS)-1) downto 0);
		
		--Output Interface for Calculated Kernel Values
		kernelCalculationsComplete, 		--kernelCalculationsComplete		: out std_logic;
		kernelIndex,          --kernelRAMRdIndex					: in std_logic_vector(8 downto 0);
		kernelValue 							--kernelValueOut						: out std_logic_vector(31 downto 0)
	);

						

		
	SVM_CLASS_EVAL_MODULE : entity WORK.svmClassEval(mixed)
   generic map(
		NUM_CLASS_MAX  =>     NUM_CLASS_MAX ,   --: integer;  -- Maximum Number of Classes the Hardware Will Handle ; WAS Fixed at 7
      NUM_MODELS     =>     NUM_MODELS,   -- : integer;  -- Number of simultaneous models to support
		TOTAL_NUM_SV   =>     TOTAL_NUM_SV,--    : integer;  -- Maximum # of SV vectors to be stored (for all models)
		MAX_SV_IN_LRG_MODEL =>  MAX_SV_IN_LRG_MODEL  --: integer;  -- Maximum # of SV vectors to be stored in the largest model
   )
	port map(
		svm_clock, svm_reset, kernelCalculationsComplete, --svm_restart,
								
		--Input Kernel Values
		kernelIndex,		--	kernelIndex			: out std_logic_vector(8 downto 0);
		kernelValue,		--	kernelValue			: in std_logic_vector(31 downto 0);
		
		model_select, 
		
		-- Databus Input for SVM Coefficient and Rho RAMs Databus
		svmModelDataBus, 			--  coeffAndRhoDataBus				: in std_logic_vector(31 downto 0);
		svmModelWrStateRst,		--coeff_rho_WrStateRst				: in std_logic;   -- Restart RAM Write state machine when '1'
		wr_clock,					--coeff_rho_clock						: in std_logic;   -- Write clock for coefficent and Rho RAMs
		coeff_rho_termSig,   	--coeff_rho_termSig					: in std_logic;
		coeff_rho_dvalid,       --coeff_rho_dvalid					: in std_logic;
		coeff_rho_dack,			--coeff_rho_dack						: in std_logic;
		forceCoeffIndexIncr,
		
		--Output Interface for Calculated Class Values
		svm_predict_complete,		--classEvalComplete					: out std_logic;
		svm_prediction					--classOut		
	);
		

	----------------------------------------------------------------------------------------------	
	-- Detection of Restart signal for SVM                                                      --
	-- Restart begins a new SVM Prediction, whereas reset, resets the entire circuit            --
	-- This is pulsed true when feature extraction is complete and the detected phase is valid  --
	----------------------------------------------------------------------------------------------
	checkForRestart: process(svm_clock)
	begin
	if(rising_edge(svm_clock)) then
		if(svm_reset = '1') then
			svm_restart <= '0';
			checkState <= lookForLow;
		else
			case checkState is
			
				when lookForLow =>
					if( (featureExtractComplete = '0') ) then
						checkState <= lookForHigh;
					end if;
					svm_restart <= '0';
						
				when lookForHigh =>
					if(featureExtractComplete = '1') then
						svm_restart <= '1';
						checkState <= lookForLow;
					end if;
				
				when others =>
					svm_restart <= '0';
					checkState <= lookForLow;
			end case;
		end if;
	end if;
	end process;
		


END ARCHITECTURE Behavioral;
