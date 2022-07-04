LIBRARY IEEE;
USE IEEE.std_logic_1164.all;
USE IEEE.std_logic_unsigned.all;
use work.limb_feature_pkg.all;
use work.z48common.all;


ENTITY UART_COMMS_TOP IS
	GENERIC(
			NUM_CLASS_MAX      : integer;  -- Maximum Number of Classes the Hardware Will Handle
			NUM_MODELS:          integer;  -- Number of simultaneous models to support
			NUM_FEATURES:        integer  -- Number of Input Feature Elements
	);
	PORT(
			RESET							:	IN std_logic;		-- Master Reset
			CLOCK							:	IN std_logic;		-- UART Clock
			uart_rxd						:	in std_logic;		-- Physical UART RX pin
			uart_txd						:	out std_logic;		-- Physical UART TX pin
			
			-- Comms to real-time 32-bit databus
			RT_uart_RX_data_bus		: out std_logic_vector(31 downto 0);	
			RT_rx_dvalid				: out std_logic;

			-- Kernel Parameters
			kernel_select 		: out std_logic_vector(1 downto 0);
			kernelp_gamma 		: out std_logic_vector(31 downto 0);
			kernelp_a 		: out std_logic_vector(31 downto 0);
			kernelp_r 		: out std_logic_vector(31 downto 0);
			kernelp_d 		: out std_logic_vector(31 downto 0);
			kernelp_d_oddflg : out std_logic;
			kernel_param_valid 	: out std_logic;
			model_selected	: out integer range 0 to (NUM_MODELS-1);
			
			------------------------------------------------
			-- Comms to internal module RAM write databus --
			------------------------------------------------
			svmModelWrStateRst		: out std_logic;  	-- Restart RAM Write state machines when '1'
			RAM_uart_Wr_RX_data_bus	: out std_logic_vector(31 downto 0);

			-- Model and Coefficient/Rho RAM write signaling (SVM Related)
			kernelRAM_term_sig		: out std_logic;
			kernelRAM_data_valid		: out std_logic;
			kernelRAM_dack				: in std_logic;
			coeffRhoRAM_term_sig		: out std_logic;
			coeffRhoRAM_data_valid	: out std_logic;
			coeffRhoRAM_dack			: in std_logic;
			forceCoeffIndexIncr	: out std_logic;
			
			-- UART Reply Data
			uart_TX_Class_Predict	: in std_logic_vector(7 downto 0);
			uart_TX_Time				: in std_logic_vector(31 downto 0);
			tx_uart_data_valid		: in std_logic;
			tx_dack						: out std_logic
		);
END UART_COMMS_TOP;




ARCHITECTURE behavioral of UART_COMMS_TOP IS 

	attribute keep: boolean;

	constant CMD_RX_SUPPORT_VECTORS		: std_logic_vector(31 downto 0) := X"00000001";
	constant CMD_RX_COEFFICIENT_DATA		: std_logic_vector(31 downto 0) := X"00000002";
	constant CMD_RX_RHO_DATA				: std_logic_vector(31 downto 0) := X"00000003";
--	constant CMD_RX_NORM_DATA				: std_logic_vector(31 downto 0) := X"00000004";
	constant CMD_RX_REALTIME_DATA			: std_logic_vector(31 downto 0) := X"00000005";
--	constant CMD_MODE_20MS 					: std_logic_vector(31 downto 0) := X"00000006";
--	constant CMD_MODE_50MS					: std_logic_vector(31 downto 0) := X"00000007";
	constant CMD_KERNEL_MODE				: std_logic_vector(31 downto 0) := X"00000008";




	component uart is
	  port (
			clk_clk                        : in  std_logic                     ;             -- clk
			reset_reset_n                  : in  std_logic                     ;             -- reset_n
			uart_0_external_connection_rxd : in  std_logic                     ;             -- rxd
			uart_0_external_connection_txd : out std_logic;                                        -- txd
			mm_bridge_0_s0_waitrequest     : out std_logic;                                        -- waitrequest
			mm_bridge_0_s0_readdata        : out std_logic_vector(31 downto 0);                    -- readdata
			mm_bridge_0_s0_readdatavalid   : out std_logic;                                        -- readdatavalid
			mm_bridge_0_s0_burstcount      : in  std_logic_vector(0 downto 0)  ; -- burstcount
			mm_bridge_0_s0_writedata       : in  std_logic_vector(31 downto 0) ; -- writedata
			mm_bridge_0_s0_address         : in  std_logic_vector(2 downto 0)  ; -- address
			mm_bridge_0_s0_write           : in  std_logic                     ;             -- write
			mm_bridge_0_s0_read            : in  std_logic                     ;             -- read
			mm_bridge_0_s0_byteenable      : in  std_logic_vector(3 downto 0)  ; -- byteenable
			mm_bridge_0_s0_debugaccess     : in  std_logic                                  -- debugaccess
	  );
	end component uart;

	
	
	--============================================--
	-- UART MODULE 16-bit ADDRESSING --
	-- 0x0 Rx Data (Lower 8 bits only)
	-- 0x1 Tx Data (Lower 8 bits only)
	-- 0x2 Status (Bit 7 is rrdy, Bit 6 is trdy)
	-- 0x3 Control
	-- 0x4 Baud Rate Divisor
	-- 0x5 End of Packet
	--============================================--
	
	-- TX Control
	type txState_TYPE is (checkTXdataValid, TXdata, wait_for_tx_done1,
                              wait_for_tx_done2, end_tx_handshake);
	signal txState : txState_TYPE;
	signal newTxByteAvail	: std_logic;
	signal txByteRead	: std_logic;
	signal txWdCount	: integer range 0 to 5;
	signal newTxByte	: std_logic_vector(7 downto 0);
	
	-- Sequence Control
	type sequence_TYPE is (clearOutInitText, endRdHandshakeInit,checkForNumClassLeft,
	 waitForNewByte, endRdHandshake, evaluateCommand,
    toggle_wr_rst_high, toggle_wr_rst_low, RX_SUPPORT_VECTORS, cmdWriteSVData,     
    waitForSVDataWritten, waitForSVAckLow, SV_TERM_END, cmdWriteRhoData,     
    waitForRhoDataWritten, waitForRhoAckLow, coeffCheckNumModelLeft,coeffCheckClassLeft,
    TOGGLE_COEFF_RHO_TERM, RX_COEFFICIENT_DATA, cmdWriteCoeffData, 
    waitForCoeffDataWritten, waitForCoeffAckLow, RX_REALTIME_DATA, 
    RX_REALTIME_DATA_DEASSERT,RX_KERNEL_MODE);
	signal sequenceState    : sequence_TYPE;
	signal lastState	: sequence_TYPE;
	signal newRxByteAvail	: std_logic;
	signal newRxByteRead	: std_logic;
	signal wordPosition	: integer range 0 to 3;
	signal byteTarget	: integer range 0 to 3 := 1;
	signal newlineCount : integer range 0 to 7;
	signal wordData		: std_logic_vector(31 downto 0);
	alias  command 		: std_logic_vector(31 downto 0) is wordData(31 downto 0); 
	signal rxWord		: integer;-- range 0 to NUM_FEATURES;
	signal delay_cnt	: integer range 0 to 5;
	signal numModelLeft	: integer range 0 to NUM_MODELS;
	signal numClass		: std_logic_vector(31 downto 0);
	signal numClassLeft	: std_logic_vector(31 downto 0);
	signal numCoeffLeft	: std_logic_vector(31 downto 0);
	signal numSVLeft		: std_logic_vector(31 downto 0);
	signal coeffInit 		: integer range 0 to 3;



	-- UART Control
	type uartState_TYPE is (setupStatusRd, setupRxRd, checkForData, readData, waitForRxCtrlProcessHandshakeA, 
								waitForRxCtrlProcessHandshakeB, transmitData, checkTxStatus);
	signal uartState			: uartState_TYPE;
	signal newRxByte	: std_logic_vector(7 downto 0);
	
	-- Inputs to UART MODULE
   signal uartWaitReq      : std_logic;
   signal uartReadData32   : std_logic_vector(31 downto 0);
   signal uartRdDvalid     : std_logic;
	-- Outputs to UART MODULE
	signal uartRd           : std_logic;
   signal uartWr           : std_logic;
	signal uartAddr			: std_logic_vector(2 downto 0);
	signal uartWriteData32	: std_logic_vector(31 downto 0);

	
	signal tap1,tap2,tap3,tap4,tap5,tap6,tap10,tap11,tap12,tap13,tap14,newWdAvail,
   tap20,tap21,tap22,tap23,tap24,tap7,tap8,tap9	: std_logic;
	attribute keep of tap1: signal is true;
	attribute keep of tap2: signal is true;
	attribute keep of tap3: signal is true;
	attribute keep of tap4: signal is true;
	attribute keep of tap5: signal is true;
	attribute keep of tap6: signal is true;
	attribute keep of tap10: signal is true;
	attribute keep of tap11: signal is true;
	attribute keep of tap12: signal is true;
	attribute keep of tap13: signal is true;
	attribute keep of tap14: signal is true;
	attribute keep of tap20: signal is true;
	attribute keep of tap21: signal is true;
	attribute keep of tap22: signal is true;
	attribute keep of tap23: signal is true;
	attribute keep of tap24: signal is true;
	attribute keep of newWdAvail: signal is true;
	
	attribute keep of uartRdDvalid: signal is true;
	attribute keep of uartWaitReq: signal is true;
	attribute keep of uartReadData32: signal is true;
	attribute keep of uartRd: signal is true;
	attribute keep of uartWr: signal is true;
	attribute keep of uartAddr: signal is true;
	attribute keep of uartWriteData32: signal is true;
	attribute keep of newTxByte: signal is true;
	attribute keep of newRxByte: signal is true;
	attribute keep of newTxByteAvail: signal is true;

	
	
	attribute keep of wordData: signal is true;
	attribute keep of rxWord: signal is true;
	attribute keep of numModelLeft: signal is true;
	attribute keep of numClass: signal is true;
	attribute keep of numClassLeft: signal is true;
	attribute keep of kernelRAM_term_sig: signal is true;
	attribute keep of numSVLeft: signal is true;
	attribute keep of coeffRhoRAM_data_valid: signal is true;
	attribute keep of forceCoeffIndexIncr: signal is true;
	attribute keep of coeffInit: signal is true;
	attribute keep of numCoeffLeft: signal is true;
	attribute keep of kernel_select: signal is true;
	attribute keep of kernelp_gamma: signal is true;
	attribute keep of kernelp_a: signal is true;
	attribute keep of kernelp_r: signal is true;
	attribute keep of kernelp_d: signal is true;
	attribute keep of model_selected: signal is true;
	attribute keep of kernel_param_valid: signal is true;
	
	
	
BEGIN

-- UART to RX Model Data
systemUART : uart PORT MAP (
		clk_clk         =>  CLOCK,
		reset_reset_n   => not RESET,
		uart_0_external_connection_rxd => uart_rxd,
		uart_0_external_connection_txd => uart_txd,
		mm_bridge_0_s0_waitrequest  	 => uartWaitReq   ,--: out std_logic;                                        -- waitrequest
		mm_bridge_0_s0_readdata  		 => uartReadData32,--: out std_logic_vector(31 downto 0);                    -- readdata
		mm_bridge_0_s0_readdatavalid 	 => uartRdDvalid,--: out std_logic;             -- readdatavalid
		mm_bridge_0_s0_burstcount  	 => "1"   ,--: in  std_logic_vector(0 downto 0)  ; -- burstcount
		mm_bridge_0_s0_writedata   	 => uartWriteData32   ,--: in  std_logic_vector(31 downto 0) ; -- writedata
		mm_bridge_0_s0_address     	 => uartAddr   ,--: in  std_logic_vector(2 downto 0)  ; -- address
		mm_bridge_0_s0_write       	 => uartWr   ,--: in  std_logic                     ;             -- write
		mm_bridge_0_s0_read        	 => uartRd   ,--: in  std_logic                     ;             -- read
		mm_bridge_0_s0_byteenable   	 => "0011"  ,--: in  std_logic_vector(3 downto 0)  ; -- byteenable
		mm_bridge_0_s0_debugaccess  	 => '0'  --: in  std_logic                                  -- debugaccess
  );
 
	

-------------------------------------------------------------------------------
-- This process gets a request to transit data from the 
-- SVM Classifier to the Limb Control.
--
-- When tx_uart_data_valid goes true, the 8-bit predicted
-- class is sent over the serial link followed by the 32-bit little endian
-- amount of time taken for the prediction.  tx_dack is then asserted.
-- tx_dack is deasserted once tx_uart_data_valid goes low again.
-- The process is then ready to send data again.
--------------------------------------------------------------------------------
Transmit_Data_Process: PROCESS(CLOCK, RESET)
BEGIN

	IF(RESET = '1') THEN		
		txState <= checkTXdataValid;
		newTxByteAvail <= '0';
		tx_dack <= '0';
		txWdCount <= 0;
		
	ELSIF(CLOCK'event AND CLOCK = '1') THEN
		CASE txState IS

			when checkTXdataValid =>
				if(tx_uart_data_valid = '1') then
					txState <= TXdata;
				end if;
				
			when TXdata =>
				txWdCount <= txWdCount + 1;
				newTxByteAvail <= '1';
				txState <= wait_for_tx_done1;
				if(txWdCount = 0) then
					newTxByte <= uart_TX_Class_Predict;
				elsif(txWdCount = 1) then
					newTxByte <= uart_TX_Time(7 downto 0);
				elsif(txWdCount = 2) then
					newTxByte <= uart_TX_Time(15 downto 8);
				elsif(txWdCount = 3) then
					newTxByte <= uart_TX_Time(23 downto 16);
				else		-- txWdCount = 4
					newTxByte <= uart_TX_Time(31 downto 24);
				end if;
--REMOVE LATER
				newTxByte(7) <= tap1 xor tap2 xor tap3 xor tap4 xor tap5 xor tap6 xor 
				tap7 xor tap8 xor tap9 xor 
				tap10 xor tap11 xor tap12 xor tap13 xor tap14 xor newWdAvail xor
				tap20 xor tap21 xor tap22 xor tap23 xor tap24;
				
			WHEN wait_for_tx_done1 =>
				if(txByteRead = '1') then
					newTxByteAvail <= '0';
					txState <= wait_for_tx_done2;
				end if;
			WHEN wait_for_tx_done2 =>
				if(txByteRead = '0') then
					txState <= checkTXdataValid;
					
					-- Check to end the data valid handshake
					if(txWdCount = 5) then
						tx_dack <= '1';
						txWdCount <= 0;
						txState <= end_tx_handshake;
					end if;
				end if;
				
			WHEN end_tx_handshake =>
				if(tx_uart_data_valid = '0') then
					tx_dack <= '0';
					txState <= checkTXdataValid;
				end if;
				
			WHEN others =>
				txState <= checkTXdataValid;
				newTxByteAvail <= '0';
				tx_dack <= '0';
				txWdCount <= 0;
		End Case;
	End if;
END Process;	






-- Command Input Sequencer Process
Command_Sequencer: PROCESS(CLOCK, RESET)
BEGIN
	IF(RESET = '1') THEN
		wordPosition <= 0;
		byteTarget   <= 3;
		newRxByteRead <= '0';
		svmModelWrStateRst <= '0';
		kernelRAM_term_sig <= '0';
		kernelRAM_data_valid <= '0';
		coeffRhoRAM_data_valid <= '0';
		coeffRhoRAM_term_sig <= '0';
		RT_rx_dvalid <= '0';
		lastState <= evaluateCommand;
		newlineCount <= 0;
		sequenceState <= clearOutInitText;
		
		tap1 <= '0';
		tap2 <= '0';
		tap3 <= '0';
		tap4 <= '0';
		tap5 <= '0';
		tap6 <= '0';
		tap7 <= '0';
		tap8 <= '0';
		tap9 <= '0';		
		tap10 <= '0';
		tap11 <= '0';
		tap12 <= '0';
		tap13 <= '0';
		tap14 <= '0';
		tap20 <= '0';
		tap21 <= '0';
		tap22 <= '0';
		tap23 <= '0';
		tap24 <= '0';
		newWdAvail <= '0';

	ELSIF(CLOCK'event AND CLOCK = '1') THEN
		kernel_param_valid <= '0';

newWdAvail <= '0';		
		tap1 <= '0';
		tap2 <= '0';
		tap3 <= '0';
		tap4 <= '0';
		tap5 <= '0';
		tap6 <= '0';
		tap7 <= '0';
		tap8 <= '0';
		tap9 <= '0';
tap10 <= '0';
tap11 <= '0';
tap12 <= '0';
tap13 <= '0';
tap14 <= '0';
		tap20 <= '0';
		tap21 <= '0';
		tap22 <= '0';
		tap23 <= '0';
		tap24 <= '0';		
		CASE sequenceState IS
		
			WHEN clearOutInitText =>
				if(newRxByteAvail = '1') then
					if(newRxByte = X"0A") then
						newlineCount <= newlineCount + 1;
					end if;
					newRxByteRead <= '1';
					sequenceState <= endRdHandshakeInit;
				end if;
			WHEN endRdHandshakeInit =>
				if(newRxByteAvail = '0') then
					newRxByteRead <= '0';
					if(newlineCount = 2) then
						sequenceState <= waitForNewByte;
					else
						sequenceState <= clearOutInitText;
					end if;
				end if;	

		
			---------------------------------------------------------------------
			-- The first Two States deal with receiving and ordering incoming
			-- bytes from the bluetooth connection.  A PC on the other end is
			-- sending the data in little endian format for this demonstration.
			---------------------------------------------------------------------
			WHEN waitForNewByte =>
				if(newRxByteAvail = '1') then
					if(wordPosition = 0) then
						wordData(7 downto 0) <= newRxByte;
					elsif(wordPosition = 1) then
						wordData(15 downto 8) <= newRxByte;
					elsif(wordPosition = 2) then
						wordData(23 downto 16) <= newRxByte;
					else
						wordData(31 downto 24) <= newRxByte;
					end if;
					newRxByteRead <= '1';
					sequenceState <= endRdHandshake;
				end if;
			WHEN endRdHandshake =>
				if(newRxByteAvail = '0') then
					newRxByteRead <= '0';
					if(wordPosition = byteTarget) then
						sequenceState <= lastState;
newWdAvail <= '1';
						wordPosition <= 0;
					else
						wordPosition <= wordPosition + 1;
						sequenceState <= waitForNewByte;
					end if;
				end if;
			
			---------------------------------------------------------------------
			-- Determine What Action to Take from incoming 16-bit commands
			-- Send them in order or else: ModeCmd, SV, RHO, Coeff!
			-- Order for Norm parameters doesnt matter
			-- RT data sent after configuration params
			--
			-- Command Invalid
			-- Command RX_SUPPORT_VECTORS		(32-bit Data Follows)
			-- Command RX_RHO_DATA			   (32-bit Data Follows, 88 samples)
			-- Command RX_COEFFICIENT_DATA	(32-bit Data Follows)
			-- Command RX_NORM_DATA				(32-bit Data Follows, 368 samples)
			-- Command RX_REALTIME_DATA		(260 samples, 16-bit Data Follows)
			---------------------------------------------------------------------
			WHEN evaluateCommand =>
				lastState <= evaluateCommand;
				sequenceState <= waitForNewByte;
				rxWord <= 0;
				byteTarget <= 3;

				if(command = CMD_RX_SUPPORT_VECTORS) then
					lastState <= RX_SUPPORT_VECTORS;
					tap10 <= '1';
					sequenceState <= toggle_wr_rst_high;
				elsif(command = CMD_RX_RHO_DATA) then
					tap11 <= '1';
					lastState <= cmdWriteRhoData;
				elsif(command = CMD_RX_COEFFICIENT_DATA) then
					tap12 <= '1';
					lastState <= RX_COEFFICIENT_DATA;
				elsif(command = CMD_RX_REALTIME_DATA) then
					tap13 <= '1';
					lastState <= RX_REALTIME_DATA;
				elsif(command = CMD_KERNEL_MODE) then
					lastState <= RX_KERNEL_MODE;			--KANE NEW
					tap14 <= '1';
				else
					-- BAD State, ignore Rx'd Command	
					wordData(23 downto 0) <= wordData(31 downto 8);
					wordPosition <= 3;
				end if;


			------------------------------------
			-- Reset RAM Write state machines --
			------------------------------------
			WHEN toggle_wr_rst_high =>
				svmModelWrStateRst <= '1';
				sequenceState <= toggle_wr_rst_low;
			WHEN toggle_wr_rst_low =>
				svmModelWrStateRst <= '0';
				sequenceState <= waitForNewByte;


			----------------------------------------------					
			-- Support Vector RAM Write Handshake Logic --
			----------------------------------------------	
			WHEN RX_SUPPORT_VECTORS =>
				if(rxWord = 0) then
					numModelLeft  <= NUM_MODELS;	--Implementation fixed at 4 models
					numClass	   <= wordData;
					numClassLeft  <= wordData;
					rxWord <= rxWord + 1;
					kernelRAM_term_sig <= '1';
					sequenceState <= SV_TERM_END;
				elsif(rxWord = 1) then
					numSVLeft <= wordData;
					rxWord     <= rxWord + 1;
					sequenceState <= waitForSVAckLow;
					tap1 <= '1';
				else
					-- Write the Support Vector to RAM
					sequenceState <= cmdWriteSVData;
				end if;
				
			
			-- SV RAM Write Handshake Logic
			WHEN cmdWriteSVData =>
				kernelRAM_data_valid <= '1';
				RAM_uart_Wr_RX_data_bus <= wordData;
				sequenceState <= waitForSVDataWritten;
			WHEN waitForSVDataWritten =>
				if(kernelRAM_dack = '1') then
					if(numSVLeft > 0) then
						numSVLeft  <= numSVLeft - 1;
					end if;
					kernelRAM_data_valid <= '0';
					sequenceState <= waitForSVAckLow;
				end if;
			WHEN waitForSVAckLow =>
tap2 <= '1';
			
				if(kernelRAM_dack = '0') then
					-- Determine if there is more data left
					if(numSVLeft > 0) then
						sequenceState <= waitForNewByte;
					else
						numClassLeft <= numClassLeft - 1;
						sequenceState <= checkForNumClassLeft;
					end if;
				end if;
				
			WHEN checkForNumClassLeft =>
				if(numClassLeft > 0) then
tap3 <= '1';
						rxWord <= 1;
						sequenceState <= waitForNewByte;
				else
						-- No More Classes Left, send the term signal
tap4 <= '1';
						numModelLeft <= numModelLeft - 1;
						numClassLeft <= numClass;	--reset number of classes
						rxWord <= 1;
						-- Send end term signal
						kernelRAM_term_sig <= '1';
						if(numModelLeft = 1) then
							RAM_uart_Wr_RX_data_bus <= X"0000DEAD";
						end if;
						sequenceState <= SV_TERM_END;
				end if;
	
						
			-- Completes toggling of the term signal.  If the last of the 4 models
			-- Was Rx'd then return to wait for the next command
			WHEN SV_TERM_END =>
				kernelRAM_term_sig <= '0';
				sequenceState <= waitForNewByte;
				if(numModelLeft = 0) then
					lastState <= evaluateCommand;	
				end if;


			-----------------------------------					
			-- RHO RAM Write Handshake Logic --
			-----------------------------------
			WHEN cmdWriteRhoData =>
				coeffRhoRAM_data_valid <= '1';
				RAM_uart_Wr_RX_data_bus <= wordData;
				sequenceState <= waitForRhoDataWritten;
			WHEN waitForRhoDataWritten =>
				if(coeffRhoRAM_dack = '1') then
					rxWord <= rxWord + 1;
					coeffRhoRAM_data_valid <= '0';
					sequenceState <= waitForRhoAckLow;
				end if;
			WHEN waitForRhoAckLow =>
tap5 <= '1';
				if(coeffRhoRAM_dack = '0') then
					if(rxWord = (((NUM_CLASS_MAX)*(NUM_CLASS_MAX-1))/2)*NUM_MODELS) then
						coeffRhoRAM_term_sig <= '1';
						sequenceState <= TOGGLE_COEFF_RHO_TERM;
					else
						sequenceState <= waitForNewByte;
					end if;
				end if;

			WHEN TOGGLE_COEFF_RHO_TERM =>
				coeffRhoRAM_term_sig <= '0';
				lastState <= evaluateCommand;
				sequenceState <= waitForNewByte;
				
tap6 <= '1';

				
			-------------------------------------------------	-			
			-- Alpha Coefficient RAM Write Handshake Logic --
			-------------------------------------------------
			WHEN RX_COEFFICIENT_DATA =>		
				forceCoeffIndexIncr <= '0';
				coeffInit <= 0;
				if(rxWord = 0) then
					-- # of classes in the model
					numModelLeft <= NUM_MODELS;	--Implementation no longer fixed at 4 models
					numClass	  <= wordData;
					numClassLeft <= wordData;
					rxWord <= rxWord + 1;
					coeffInit <= 1;
					forceCoeffIndexIncr <= '1';
					tap7 <= '1';
				elsif(rxWord < (NUM_MODELS+1)) then
					-- Model Offsets 1 to NUM_MODELS, just write them to RAM
					rxWord <= rxWord + 1;
					coeffInit <= 1;
					forceCoeffIndexIncr <= '1';
					tap8 <= '1';
				elsif(rxWord = (NUM_MODELS+1)) then
					-- Number of Coefficients for the Current Model/Class
					numCoeffLeft   <= wordData;
					rxWord     		<= rxWord + 1;
					forceCoeffIndexIncr <= '1';
					tap9 <= '1';
				else
					numCoeffLeft  <= numCoeffLeft - 1;
				end if;
				sequenceState <= cmdWriteCoeffData;
				
			-- Coefficient RAM Write Handshake Logic
			WHEN cmdWriteCoeffData =>
				coeffRhoRAM_data_valid <= '1';
				RAM_uart_Wr_RX_data_bus <= wordData;
				sequenceState <= waitForCoeffDataWritten;
				
				
			WHEN waitForCoeffDataWritten =>
				if(coeffRhoRAM_dack = '1') then
					coeffRhoRAM_data_valid <= '0';
					forceCoeffIndexIncr <= '0';
					sequenceState <= waitForCoeffAckLow;
				end if;
			WHEN waitForCoeffAckLow =>
				if(coeffRhoRAM_dack = '0') then
tap20 <= '0';
					-- Determine if there is more data left, or if we are in init
					if( (numCoeffLeft > 0) OR (coeffInit = 1) ) then
						sequenceState <= waitForNewByte;
					else
						numClassLeft <= numClassLeft - 1;
						sequenceState <= coeffCheckClassLeft;
					end if;
				end if;
				
			WHEN coeffCheckClassLeft =>
				if(numClassLeft > 0) then
					rxWord <= (NUM_MODELS+1);
					sequenceState <= waitForNewByte;
						
					tap21 <= '1';
				else
					-- No More Classes Left, This was the last class in the current model
					numModelLeft <= numModelLeft - 1;
					sequenceState <= coeffCheckNumModelLeft;
				end if;
				
			WHEN coeffCheckNumModelLeft =>
				if(numModelLeft > 0) then
					numClassLeft <= numClass;
					sequenceState <= waitForNewByte;
					rxWord <= (NUM_MODELS+1);							
					tap22 <= '1';
				else
					-- Done, send end term signal
					coeffRhoRAM_term_sig <= '1';
					sequenceState <= TOGGLE_COEFF_RHO_TERM;			
					tap23 <= '1';
				end if;

				
			-----------------------------------------------------
			-- Real-time A/D Traffic                           --
			--     Rx samples of real-time data and put on     --
			--     the feature extract bus.  When all samples  --
			--     have been received, go back to waiting for  --
			--     the next command to arrive.                 --
			-----------------------------------------------------
			WHEN RX_REALTIME_DATA =>
				RT_uart_RX_data_bus <= wordData(31 downto 0);
				RT_rx_dvalid <= '1';
				delay_cnt <= 0;
				rxWord <= rxWord + 1;
				sequenceState <= RX_REALTIME_DATA_DEASSERT;

			WHEN RX_REALTIME_DATA_DEASSERT =>
			tap24 <= '1';
				delay_cnt <= delay_cnt + 1;
				if(delay_cnt = 4) then
					RT_rx_dvalid <= '0';
					if(rxWord = NUM_FEATURES) then
						byteTarget <= 3;
						lastState <= evaluateCommand;
					end if;
					sequenceState <= waitForNewByte;
				end if;


			-----------------------------------------------
			-- Receive Kernel Parameters
			-----------------------------------------------
			WHEN RX_KERNEL_MODE =>
				rxWord <= rxWord + 1;
				sequenceState <= waitForNewByte;
				if(rxWord = 0) then
					kernel_select <= wordData(1 downto 0);
					kernelp_d_oddflg <= wordData(31);
				elsif(rxWord = 1) then
					kernelp_gamma <= wordData;
				elsif(rxWord = 2) then
					kernelp_a <= wordData;
				elsif(rxWord = 3) then
					kernelp_r <= wordData;
				elsif(rxWord = 4) then
					kernelp_d <= WordData;
				elsif(rxWord = 5) then
					model_selected <= int(WordData);
					kernel_param_valid <= '1';
					lastState <= evaluateCommand;
				end if;

			WHEN others =>
				wordPosition <= 0;
				byteTarget   <= 3;
				newRxByteRead <= '0';
				svmModelWrStateRst <= '0';
				kernelRAM_term_sig <= '0';
				kernelRAM_data_valid <= '0';
				coeffRhoRAM_data_valid <= '0';
				coeffRhoRAM_term_sig <= '0';
				RT_rx_dvalid <= '0';
				newlineCount <= 0;
				sequenceState <= clearOutInitText;
				lastState <= evaluateCommand;
				
		end case;
	end if;
end process;







	
		

	
--============================================--
-- UART MODULE 16-bit ADDRESSING --
-- 0x0 Rx Data (Lower 8 bits only)
-- 0x1 Tx Data (Lower 8 bits only)
-- 0x2 Status (Bit 7 is rrdy, Bit 6 is trdy)
-- 0x3 Control
-- 0x4 Baud Rate Divisor
-- 0x5 End of Packet
--============================================--
-- This process receives 8-bit little endian UART data and puts
-- it in the FIFO	as 16-bit big endian words
RX_TX_UART_Data: PROCESS(CLOCK, RESET)
BEGIN
	IF(RESET = '1') THEN
		newRxByteAvail <= '0';
		txByteRead		<= '0';
		uartRd <= '0';
		uartWr <= '0';
		uartState <= setupStatusRd;

	ELSIF(CLOCK'event AND CLOCK = '1') THEN

		uartRd   <= '0';
		uartWr   <= '0';
	
		CASE uartState IS
	
			WHEN setupStatusRd =>
				if(uartWaitReq = '0') then
					uartAddr <= "010";		-- STATUS Register
					uartRd   <= '1';			-- UART Read Request
					uartState <= checkForData;
				end if;
				
			WHEN setupRxRd =>
				if(uartWaitReq = '0') then
					uartAddr <= "000";		-- STATUS Register
					uartRd   <= '1';			-- UART Read Request
					uartState <= readData;
				end if;
				
			-- Look for new incoming data or whether an outgoing response
			-- needs to be issued.  Give precedence to new data
			WHEN checkForData =>
				if(uartRdDvalid = '1') then
					if(uartReadData32(7) = '1') then
						if(uartWaitReq = '0') then
							uartAddr <= "000";		-- STATUS Register
							uartRd   <= '1';			-- UART Read Request
							uartState <= readData;
						else
							uartState <= setupRxRd;
						end if;
					elsif((newTxByteAvail = '1') AND ((uartReadData32(6) = '1')) AND (uartWaitReq = '0')) then
						uartAddr <= "001";	-- TX Register
						uartWriteData32(7 downto 0) <= newTxByte;
						txByteRead <= '1';
						uartWr <= '1';
						uartState <= transmitData;
					else
						-- Status Register read, but no action to take, 
						-- perform another read from the Status Register
						uartState <= setupStatusRd;
					end if;
				end if;
				
			-- Receive Data States
			WHEN readData =>
				if(uartRdDvalid = '1') then
					newRxByte <= uartReadData32(7 downto 0);
					newRxByteAvail <= '1';
					uartState <= waitForRxCtrlProcessHandshakeA;
				end if;
			WHEN waitForRxCtrlProcessHandshakeA =>
				if(newRxByteRead = '1') then
					newRxByteAvail <= '0';
					uartState <= waitForRxCtrlProcessHandshakeB;
				end if;
			WHEN waitForRxCtrlProcessHandshakeB =>
				if(newRxByteRead = '0') then
					uartState <= setupStatusRd;
				end if;
			
			-- Transmit Data States
			WHEN transmitData =>					--Probably dont need this state
				uartState <= checkTxStatus;
			WHEN checkTxStatus =>
				if(newTxByteAvail = '0') then
					txByteRead <= '0';
					uartState <= setupStatusRd;
				end if;
				
			WHEN OTHERS =>
				newRxByteAvail <= '0';
				txByteRead		<= '0';
				uartRd <= '0';
				uartWr <= '0';
				uartState <= setupStatusRd;
				
		END CASE;
	END IF;
END PROCESS;
				
	
END ARCHITECTURE behavioral;
