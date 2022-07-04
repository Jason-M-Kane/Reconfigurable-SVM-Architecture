This executable was created to:  
1. Transmit the model data to the support vector machine hardware over bluetooth  
2. Command the start of classification  
3. Report the response time of the FPGA hardware  

Additional Notes for Bluetooth Device Usage:  
AT+AB EnableBond 002243BFB748 1234  
AT+AB SPPConnect 002243BFB748  

After typing the SPPConnect, on the Windows PC, allow the device to connect.  After this COM PORT COMMS can occur.  
