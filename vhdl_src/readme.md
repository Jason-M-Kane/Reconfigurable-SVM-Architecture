VHDL Source and Quartus project files  

To build for a particular set of features/classes/model size, modify the associated VHDL generics  
in svm_top_test.vhd

	constant NUM_FEATURES 			: integer := 16;
	constant NUM_CLASS_MAX			: integer := 26;
	constant NUM_MODELS   			: integer := 1;--4;
	constant TOTAL_NUM_SV 			: integer := 15000;
	constant MAX_SV_IN_LRG_MODEL	: integer := 14610;

Communication to the FPGA occurs via serial currently as this is just a prototype demonstration  
In our lab setup, we used a Bluetooth to serial adapter for portability, but a serial cable will work just fine.  
Keep in mind to use the proper voltage levels for the Stratix V.  

Note: Stratix V Devices require an active Altera/Intel Quartus License  
