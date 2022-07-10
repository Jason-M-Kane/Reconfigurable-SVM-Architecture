# Reconfigurable-SVM-Architecture
A Reconfigurable Support Vector Machine Architecture in VHDL for Altera Stratix V  
VHDL and Test Injection Software was developed in support of IEEE Conference Paper "A Reconfigurable Multiclass Support Vector Machine Architecture for Real-Time Embedded Systems Classification", published for the 15th Annual IEEE Symposium on Field-Programmable Custom Computing Machines (FCCM)   
https://doi.org/10.1109/FCCM.2015.24  

The default implemented bench test design expects that a Windows PC is configured with the Test injection software and a USB bluetooth transmitter or serial port to send data/commands to the FPGA and receive results.  

The Altera Stratix V DSP Edition reference board is the target for the VHDL implementation.  
The FPGA is set up to have:  
&nbsp;&nbsp;&nbsp;&nbsp;A serial TX line on hsma_d(1).  [Pin 42 on J1, 2.5V I/O, AK29.  Pin 4 on header.]  
&nbsp;&nbsp;&nbsp;&nbsp;A serial RX line on hsma_d(3).  [Pin 44 on J1, 2.5V I/O, AP28.  Pin 6 on header.]  

For direct serial communications, a circuit is required to adjust the voltage levels as needed.
For bluetooth communicaions, a bluetooth to serial microcontroller (and possibly voltage level circuit) is required.

Note: Stratix V Devices require an active Altera/Intel Quartus License  
