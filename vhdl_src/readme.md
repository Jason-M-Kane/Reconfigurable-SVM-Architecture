VHDL Source and Quartus project files  

To build for a particular set of features/classes/model size, modify the associated VHDL generics  
in svm_top_test.vhd:

constant NUM_FEATURES 			: integer := 16;  
constant NUM_CLASS_MAX			: integer := 26;  
constant NUM_MODELS   			: integer := 1;  
constant TOTAL_NUM_SV 			: integer := 15000;  
constant MAX_SV_IN_LRG_MODEL		: integer := 14610;  

Where:  
&nbsp;&nbsp;&nbsp; *NUM_FEATURES* is the number of features associated with the model.  
&nbsp;&nbsp;&nbsp; *NUM_CLASS_MAX* is the maximum number of classes the design will handle.   
&nbsp;&nbsp;&nbsp; *NUM_MODELS* is the number of unique models that the FPGA will simulataneously keep in local Block RAM.  
&nbsp;&nbsp;&nbsp; *TOTAL_NUM_SV* is total number of support vectors required to be stored.  
&nbsp;&nbsp;&nbsp; *MAX_SV_IN_LRG_MODEL* is the number of support vectors present in the largest model.  

The features and class parameters are used to construct an optimal set of hardware that will function up to the defined limitations. In the case of the kernel unit, our VHDL code uses the maximum number of features to construct an optimal-sized adder tree. The coefficient weighting and vote units use the maximum number of classes to determine the required amount of redundant MAC blocks and voting counters. The remaining three parameters are used to characterize the memory subsystem.  

The total number of support vectors parameter, in combination with the maximum number of classes determines the amount of memory required for model data storage. To access a particular model’s data, an index to the start of that data is sent to the hardware along with kernel parameters. The maximum number of models parameter is used to determine the maximum number of supported models, and therefore the total number of unique model indices that may exist in the system. The final parameter, the maximum number of support vectors in the largest model, is used to determine the amount of the RAM required by the kernel unit.  

For this demonstration project, the Windows test executable is used to load model data and stream features into the FPGA over the serial UART interface.  In an actual application the model data would likely be preloaded and features would be streamed in real-time from external interfaces.    

