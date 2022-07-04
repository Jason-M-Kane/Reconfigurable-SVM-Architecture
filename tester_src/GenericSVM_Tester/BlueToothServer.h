#ifndef _BT_SERVER_API_H
#define _BT_SERVER_API_H


/* Function Prototypes */
int sendNormParams();
int sendModelData();
int sendKernelData(int model);
int sendRTData(float * Data);
int setupBluetooth();
int recvClass(unsigned short *classification, double* classificationTime);
int closeBTComms();
int send50msData();
int send20msData();


#endif /* _BT_SERVER_API_H */
