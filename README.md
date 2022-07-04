# Reconfigurable-SVM-Architecture
A Reconfigurable Support Vector Machine Architecture in VHDL for Altera Stratix V  
VHDL and Test Injection Software was developed in support of IEEE Conference Paper "A Reconfigurable Multiclass Support Vector Machine Architecture for Real-Time Embedded Systems Classification", published for the 15th Annual IEEE Symposium on Field-Programmable Custom Computing Machines (FCCM)   
https://doi.org/10.1109/FCCM.2015.24  

The bench test design expects that a Windows PC is configured with the Test injection software and a USB bluetooth transmitter.  
The Altera Stratix V DSP Edition reference board is the target for the VHDL implementation.  An STP ??? bluetooth device is attached to pins ?? and ?? to allow for the hardware to receive model data and transmit responses back to the test injector.  To deploy in an actual system, the interface to the Stratix V would need to be modified.    

Note: Stratix V Devices require an active Altera/Intel Quartus License  
