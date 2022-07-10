This executable was created to:  
&nbsp;&nbsp;&nbsp;&nbsp; 1. Transmit the model data to the support vector machine hardware over a comm port.  
&nbsp;&nbsp;&nbsp;&nbsp; 2. Command the start of classification.  
&nbsp;&nbsp;&nbsp;&nbsp; 3. Report the response time of the FPGA hardware.  

Before running, adjust the following in config.h and recompile:  
&nbsp;&nbsp;&nbsp;&nbsp; A.) COM_PORT_TO_USE:  Should match that of the serial port or bluetooth device being used.  
&nbsp;&nbsp;&nbsp;&nbsp; B.) Model Selection:  Only define one of the models in this file.  If a new model needs to be imported, the code will need to be adapted accordingly in the config file.  
  
Note:  This software will currently only run on Windows as it makes use of specific Windows API calls.  

  
**Usage:  Generic_SVM_Tester.exe**

