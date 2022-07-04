// BlueTooth Test.cpp : Bluetooth TX/RX Routines.
//
#include <windows.h>
#include <WinBase.h>
#include <stdio.h>
#include "config_Flgs.h"
#include "norm_params.h"

#undef DBG_DATA_SEND

#define linear 0
#define polynomial 1
#define rbf 2
#define sigmoid 3

#ifdef DBG_DATA_SEND
FILE* test_output = NULL;
int G_FST_SEND = 1;
#endif

/* Function Prototypes */
int sendNormParams();
int sendModelData();
int sendKernelData(int model);
int sendRTData(float * Data);
int setupBluetooth();
int recvClass(unsigned short *classification, double* classificationTime);


static HANDLE serialHandle;

int lastError;

static int linenum = 0;
int send20msData()
{
	unsigned int message = 0x6;
	DWORD status;

    if(WriteFile(serialHandle,&message,sizeof(unsigned int),&status,NULL) == 0)
    {
        lastError = GetLastError();
        printf("Error %d, writting data to serial port.\n",lastError);
        return -1;
    }

	return 0;
}


int send50msData()
{
	unsigned int message = 0x7;
	DWORD status;

    if(WriteFile(serialHandle,&message,sizeof(unsigned int),&status,NULL) == 0)
    {
        lastError = GetLastError();
        printf("Error %d, writting data to serial port.\n",lastError);
        return -1;
    }

	return 0;
}


int setupBluetooth()
{

    DCB portConfig;
    COMMTIMEOUTS timeout;
    DWORD lastError;

    //Initialize Serial Communications
    serialHandle = CreateFile(COM_PORT_TO_USE,		  /* Port to open   */
        GENERIC_READ | GENERIC_WRITE,         /* Device Mode    */
        0,                                    /* Not Shared     */
        NULL,                                 /* Security       */
        OPEN_EXISTING,                        /* Action to take */
        0,
        NULL);
    if( (serialHandle) == NULL)
    {
        lastError = GetLastError();
        printf("Error %d, Could not open serial port.\n",lastError);
        return -1;
    }

    //Get the current serial port config
    if(GetCommState( (serialHandle),&portConfig) == 0)
    {
        lastError = GetLastError();
        printf("Error %d, unable to retrieve port settings\n",lastError);
        CloseHandle(serialHandle);        
        return -1;
    }

    //Adjust serial port configuration
    portConfig.BaudRate = 115000;
    portConfig.StopBits = ONESTOPBIT;
    portConfig.Parity = 0;
    portConfig.ByteSize = 8;

    //Set the new configuration
    if(SetCommState( (serialHandle),&portConfig) == 0)
    {
        lastError = GetLastError();
        printf("Error %d, unable to alter existing port configuration\n",lastError);
        CloseHandle(serialHandle);
        return -1;
    }

    //Set up Serial Port Timeouts (all times are in ms)
    timeout.ReadIntervalTimeout = 1000;         /* Time allowed to elapse between the arrival of two characters */
    timeout.ReadTotalTimeoutMultiplier = 1000;  /* Total time-out period for read operations */
    timeout.ReadTotalTimeoutConstant = 1000;    /* Constant used to calculate the total time-out period for read operations */
    timeout.WriteTotalTimeoutMultiplier = 50;   /* Multiplier used to calculate the total time-out period for write operations */
    timeout.WriteTotalTimeoutConstant = 50;     /* Constant used to calculate the total time-out period for write operations */
    
    //Set the Device Timeouts
    if(SetCommTimeouts(serialHandle,&timeout) == 0)
    {
        lastError = GetLastError();
        printf("Error %d, unable to set device timeout parameters.\n",lastError);
        CloseHandle(serialHandle);
        return -1;
    }

	printf("Serial Port Open.\n");

    return 0;
}




int recvClass(unsigned short *classification, double* classificationTime)
{
	char mytemp[10];
	unsigned int time;
	int bytes_recvd = 0;
	DWORD status;

	while(bytes_recvd < 5)
	{
		if(ReadFile(serialHandle,&mytemp,5 - bytes_recvd, &status,NULL) == 0)
		{
			lastError = GetLastError();
			printf("Error %d, reading data from serial port.\n",lastError);
			return -1;
	    }


		bytes_recvd += status;
	}
	*classification = (unsigned short)mytemp[0];
	memcpy(&time,&mytemp[1],4);
	*classificationTime = (double)time / (FPGA_CLOCK_FREQ_MHZ*1000.0);

	return 0;
}




int sendRTData(float * Data)
{
	DWORD status;
	int temp;

	struct{
		unsigned int mid;
		float features[NUM_FEATURES];
	} RTDataMsg;

	RTDataMsg.mid = 0x5;
	for (temp=0;temp<NUM_FEATURES;temp++) RTDataMsg.features[temp] = Data[temp];

#ifdef DBG_DATA_SEND
	if(G_FST_SEND == 1)
		fwrite(&RTDataMsg,sizeof(RTDataMsg),1,test_output);
#endif

    if(WriteFile(serialHandle,&RTDataMsg,sizeof(RTDataMsg),&status,NULL) == 0)
    {
        lastError = GetLastError();
        printf("Error %d, writting data to serial port.\n",lastError);
#ifndef DBG_DATA_SEND
        return -1;
#endif
    }

#ifdef DBG_DATA_SEND
	if(G_FST_SEND == 1)
	{
		fclose(test_output);
		G_FST_SEND = 0;
	}
#endif

	return 0;
}




int sendNormParams()
{
	char *normParamsMsg = NULL;
	char *currPtr;
	DWORD status;

	if(!(normParamsMsg = (char *)malloc(8*NUM_FEATURES*sizeof(double) + sizeof(unsigned long))))
	{
		printf("ERROR allocating memory for normParams message!!\n");
		fflush(stdin);
		getchar();
		return -1;
	}

	*((unsigned long *)normParamsMsg) = 4; /* MSG ID 4 = Normalization Parameters */
	currPtr = normParamsMsg + sizeof(unsigned long);

	memcpy(currPtr, phase1_mean, NUM_FEATURES*sizeof(double));
	currPtr += NUM_FEATURES*sizeof(double);
	memcpy(currPtr, phase2_mean, NUM_FEATURES*sizeof(double));
	currPtr += NUM_FEATURES*sizeof(double);
	memcpy(currPtr, phase3_mean, NUM_FEATURES*sizeof(double));
	currPtr += NUM_FEATURES*sizeof(double);
	memcpy(currPtr, phase4_mean, NUM_FEATURES*sizeof(double));
	currPtr += NUM_FEATURES*sizeof(double);
	memcpy(currPtr, phase1_SD, NUM_FEATURES*sizeof(double));
	currPtr += NUM_FEATURES*sizeof(double);
	memcpy(currPtr, phase2_SD, NUM_FEATURES*sizeof(double));
	currPtr += NUM_FEATURES*sizeof(double);
	memcpy(currPtr, phase3_SD, NUM_FEATURES*sizeof(double));
	currPtr += NUM_FEATURES*sizeof(double);
	memcpy(currPtr, phase4_SD, NUM_FEATURES*sizeof(double));

	if(WriteFile(serialHandle,normParamsMsg,8*NUM_FEATURES*sizeof(double) + sizeof(unsigned long),&status,NULL) == 0)
    {
        lastError = GetLastError();
        printf("Error %d, writting data to serial port.\n",lastError);
		free(normParamsMsg);
        return -1;
    }

	free(normParamsMsg);

	return 0;
}



//KANE -- yeah this isnt auto-generated to size, i got lazy.

char kernel_modelFile[10][300];

int sendKernelData(int model)
{
	FILE *modelData[NUM_MODELS];
	unsigned int i;
	DWORD status;
	static char cmd[100];	//temp line holder

	////////////Added for reading kernel - degree - gamma - Coef)
	int kernel[NUM_MODELS];
	int degree[NUM_MODELS];
	float gamma[NUM_MODELS];
	float coef0[NUM_MODELS];
	
	for (i=0;i<NUM_MODELS;i++) kernel[i] = 0;
	for (i=0;i<NUM_MODELS;i++) degree[i] = 0;
	for (i=0;i<NUM_MODELS;i++) gamma[i] = 0.0;
	for (i=0;i<NUM_MODELS;i++) coef0[i] = 0.0;

	for (i=0;i<NUM_MODELS;i++)
	{
		modelData[i] = fopen(kernel_modelFile[i], "r");
		while(1)
		{
			fscanf(modelData[i],"%80s",cmd);
			if(strcmp(cmd,"svm_type")==0) 
			{
				fscanf(modelData[i],"%80s",cmd);
			}
			else if(strcmp(cmd,"kernel_type")==0)
				{
					fscanf(modelData[i],"%80s",cmd);
					if(strcmp("linear",cmd)==0) kernel[i] = linear;
					else if(strcmp("polynomial",cmd)==0) kernel[i] = polynomial;
					else if(strcmp("rbf",cmd)==0) kernel[i] = rbf;
					else if(strcmp("sigmoid",cmd)==0) kernel[i] = sigmoid;
					else printf("unknown svm type.\n");
					printf("Kernel_Type %i = %s\n",i,cmd);
				}
			else if(strcmp(cmd,"degree")==0)
				fscanf(modelData[i],"%d",&degree[i]);
			else if(strcmp(cmd,"gamma")==0)
				fscanf(modelData[i],"%f",&gamma[i]);
			else if(strcmp(cmd,"coef0")==0)
				fscanf(modelData[i],"%f",&coef0[i]);
			else
			{
				fclose(modelData[i]);
				break;
			}
		}
	}

	for (i=0;i<NUM_MODELS;i++) printf("Kernel %i = %i\n",i,kernel[i]);
	for (i=0;i<NUM_MODELS;i++) printf("Degree %i = %i\n",i,degree[i]);
	for (i=0;i<NUM_MODELS;i++) printf("Gamma %i = %f\n",i,gamma[i]);
	for (i=0;i<NUM_MODELS;i++) printf("Coef0 %i = %f\n",i,coef0[i]);

	struct{
		unsigned int mid;
		unsigned int kernel;
		float gamma1;
		float gamma2;
		float coef0;
		float degree;
		unsigned int ModelNum;
	} KernelDataMsg;

	KernelDataMsg.mid = 0x8;
	KernelDataMsg.kernel = kernel[model];
	KernelDataMsg.degree = (float)degree[model];
	KernelDataMsg.gamma1 = gamma[model];
	KernelDataMsg.gamma2 = gamma[model];
	KernelDataMsg.coef0 = coef0[model];
	KernelDataMsg.ModelNum = model;

	/* Set odd bit for polynomial */
	if((KernelDataMsg.kernel == polynomial) && (degree[model] & 0x1))
	{
		KernelDataMsg.kernel |= 0x80000000;
	}

	/* Fix parameters for RBF */
	if(kernel[model] == rbf)
	{
		KernelDataMsg.gamma1 *= (float)-1.0; 
		KernelDataMsg.gamma2 *= (float)-1.0; 
	}

#ifdef DBG_DATA_SEND
	fwrite(&KernelDataMsg,sizeof(KernelDataMsg),1,test_output);
#endif

	if(WriteFile(serialHandle,&KernelDataMsg,sizeof(KernelDataMsg),&status,NULL) == 0)
    {
        lastError = GetLastError();
        printf("Error %d, writting Kernel Data Msg to serial port.\n",lastError);
#ifndef DBG_DATA_SEND
        return -1;
#endif
    }

	return 0;
}




typedef struct 
{
	unsigned long msgID;
	unsigned long numClasses;
	unsigned long offset[NUM_MODELS + 1];
} coeffMsgHdrType;

char modelFile[10][300];

#define NUM_RHO_VALUES		(int) ((NUM_CLASS*(NUM_CLASS-1))/2)
int sendModelData()
{
	char *modelDataMsg = NULL;
	char *coeffMsg = NULL;
	unsigned long msgSize, coeffMsgSize;
	FILE *modelData[NUM_MODELS];
	unsigned int *classes; 
	unsigned int i,j,k,m;
	unsigned long *currPtr;
	unsigned long *currCoeffPtr;
	unsigned long *currRhoPtr;
	unsigned int numVectors;
	unsigned int numClasses;
	unsigned int numElements;
	coeffMsgHdrType coeffHdr;
	
	/* KANE FIX NEW */
	static float rhoMsg[NUM_MODELS*NUM_RHO_VALUES + 1];
	int rtnVal;
	DWORD status;
#ifdef DBG_DATA_SEND
    test_output = NULL;
    G_FST_SEND = 1;
	test_output = fopen("output_test.bin","wb");
#endif
	/***************************/
	/* Parse header of models  */
	/***************************/
	coeffHdr.msgID = 2;
	coeffHdr.offset[0] = (1 + NUM_MODELS);
	/* KANE FIX NEW */
	memset(rhoMsg, 0xff, (1 + NUM_MODELS*NUM_RHO_VALUES)*sizeof(float));

	currRhoPtr = (unsigned long *)rhoMsg;
	*currRhoPtr = 3; /* msg ID */

	msgSize = 2*sizeof(unsigned long); /* msg ID + numClasses */
	coeffMsgSize = sizeof(coeffMsgHdrType) - sizeof(unsigned long);

	for(i = 0; i < NUM_MODELS; i++)
	{
		if(!(modelData[i] = fopen(modelFile[i], "r")))
		{
			printf("ERROR opening model data file %d!\n", i + 1);
			return -1;
		}

		/* read up to first float value, assume this is gamma */
		while((rtnVal = fscanf(modelData[i], "%f", (float *)&numVectors)) == 0) fgetc(modelData[i]);

		if(rtnVal == EOF || rtnVal < 0) /* ERROR */
		{
			printf("ERROR parsing model data %d header: cannot find gamma!\n", i + 1);
			return -1;
		}

		/* read next int, assume it is numClasses */
		while((rtnVal = fscanf(modelData[i], "%u", &numClasses)) == 0) fgetc(modelData[i]);

		if(rtnVal == EOF || rtnVal < 0) /* ERROR */
		{
			printf("ERROR parsing model data %d header: cannot find numClasses!\n", i + 1);
			return -1;
		}

		/* read next int, assume it is numVectors */
		while((rtnVal = fscanf(modelData[i], "%u", &numVectors)) == 0) fgetc(modelData[i]);

		if(rtnVal == EOF || rtnVal < 0) /* ERROR */
		{
			printf("ERROR parsing model data %d header: cannot find numVectors!\n", i + 1);
			return -1;
		}

		/* read next int, assume it is numElements */
		while((rtnVal = fscanf(modelData[i], "%u", &numElements)) == 0) fgetc(modelData[i]);
		printf("numElements = %d\n",numElements);

		if(rtnVal == EOF || rtnVal < 0) /* ERROR */
		{
			printf("ERROR parsing model data %d header: cannot find numVectors!\n", i + 1);
			return -1;
		}

		/* KANE -- FIXED OFFSET HERE */
		coeffHdr.offset[i+1] = coeffHdr.offset[i] + numVectors + numClasses;
		msgSize += numClasses*sizeof(unsigned long) + numVectors*numElements*sizeof(float);
		coeffMsgSize += ((numClasses - 1)*numVectors + numClasses)*sizeof(unsigned long);
	}

	coeffHdr.numClasses = numClasses;


	/****************************/
	/* Allocate memory for msgs */
	/****************************/
	if(!(modelDataMsg = (char *)malloc(msgSize)))
	{
		printf("ERROR allocating %u bytes of memory!!\n", msgSize);
		return -1;
	}

	if(!(coeffMsg = (char *)malloc(coeffMsgSize)))
	{
		printf("ERROR allocating %u bytes of memory!!\n", coeffMsgSize);
		free(modelDataMsg);
		return -1;
	}	


	currPtr = (unsigned long *) modelDataMsg;

	*currPtr = 1; /* msg ID */
	currPtr++;
	*currPtr = numClasses;
	currPtr++;

	memcpy(coeffMsg, &coeffHdr, sizeof(coeffMsgHdrType));
	currCoeffPtr = (unsigned long *)(coeffMsg + sizeof(coeffMsgHdrType) - sizeof(unsigned long));

	if(!(classes = (unsigned int *)malloc(numClasses*sizeof(unsigned int))))
	{
		printf("ERROR allocating memory for class SV totals!!\n");
		free(modelDataMsg);
		free(coeffMsg);
		return -1;
	}

	for(m = 0; m < NUM_MODELS; m++)
	{
		/* KANE FIX NEW */
		currRhoPtr = (unsigned long *)(rhoMsg + m*NUM_RHO_VALUES + 1); /* offset to current model */

		/* write out Rho values for model */
		for(i = 0; i < ((numClasses * (numClasses - 1)) / 2); i++) 
		{
			while((rtnVal = fscanf(modelData[m], "%f", (float *)currRhoPtr)) == 0) fgetc(modelData[m]);
			*(float *)currRhoPtr *= -1.f; //Another Friking Change For Jay

			if(rtnVal == EOF || rtnVal < 0) /* ERROR */
			{
				printf("ERROR parsing model data header: cannot find rho value %d for model %d!\n", i + 1,m);
				free(modelDataMsg);
				free(coeffMsg);
				return -1;
			}
			currRhoPtr++;
		}

		/* skip class labels */
		for(i = 0; i < numClasses; i++)
		{
			while((rtnVal = fscanf(modelData[m], "%u", &numVectors)) == 0) fgetc(modelData[m]);

			if(rtnVal == EOF || rtnVal < 0) /* ERROR */
			{
				printf("ERROR parsing model data header: cannot find class label %d!\n", i + 1);
				free(modelDataMsg);
				free(coeffMsg);
				return -1;
			}
		}

		/* parse vector totals for each class */
		for(i = 0; i < numClasses; i++)
		{
			while((rtnVal = fscanf(modelData[m], "%u", &classes[i])) == 0) fgetc(modelData[m]);

			if(rtnVal == EOF || rtnVal < 0) /* ERROR */
			{
				printf("ERROR parsing model data header: cannot find vector total for class %d!\n", i + 1);
				free(modelDataMsg);
				free(coeffMsg);
				return -1;
			}
		}

		/************************************/
		/* write vector data for each class */
		/************************************/
		for(k = 0; k < numClasses; k++)
		{
			*currPtr = classes[k] * NUM_FEATURES; /* number of SVs */
			currPtr++;

			*currCoeffPtr = classes[k] * (numClasses - 1);
			currCoeffPtr++;

			for(i = 0; i < classes[k]; i++)
			{
				for(j = 0; j < numClasses - 1; j++) /* write out coefficients */
				{
					while((rtnVal = fscanf(modelData[m], "%f", (float *)(currCoeffPtr))) == 0) fgetc(modelData[m]);

					if(rtnVal == EOF || rtnVal < 0) /* ERROR */
					{
						printf("ERROR parsing model data %d header: cannot find rho value %d!\n", m + 1, i + 1);
						free(modelDataMsg);
						free(coeffMsg);
						return -1;
					}

					currCoeffPtr++;


				}
linenum++;
				for(j = 0; j < NUM_FEATURES; j++) /* write out the vectors */
				{
					float junk=0.0; //Kane Fix
					while((rtnVal = fscanf(modelData[m], "%f", &junk)) == 0) //Kane Fix
						fgetc(modelData[m]);//Kane Fix
					while((rtnVal = fscanf(modelData[m], "%f", (float *)(currPtr))) == 0) 
						fgetc(modelData[m]);

					if(rtnVal == EOF || rtnVal < 0) /* ERROR */
					{
						printf("ERROR parsing model vector data for model %d; jth term = %d!\n", m + 1, j);
						printf("number of support vector elements = %d\n", numElements);
						free(modelDataMsg);
						free(coeffMsg);
						return -1;
					}
					currPtr++;
					if ((int)junk == (j+1))
					{}
					else 
					{
						printf("Element Length Mismatch (line %d, exp element %d,got element %d) - Probably Sparse Formatting\n",(linenum+10),(int)junk-1,(int)junk);
						printf("\n");
						j = (int)junk - 1;
					}
				}
			}
		}
		fclose(modelData[m]);
	}
	free(classes);

#ifdef DBG_DATA_SEND
	fwrite(modelDataMsg,msgSize,1,test_output);
#endif

	if(WriteFile(serialHandle,modelDataMsg,msgSize,&status,NULL) == 0)
    {
        lastError = GetLastError();
        printf("Error %d, writting data to serial port.\n",lastError);
#ifndef DBG_DATA_SEND
		free(modelDataMsg);
        return -1;
#endif
    }
	free(modelDataMsg);

#ifdef DBG_DATA_SEND
	fwrite(rhoMsg,(NUM_RHO_VALUES*NUM_MODELS + 1)*sizeof(float),1,test_output);
#endif

	/* KANE FIX - NEW */
	if(WriteFile(serialHandle,rhoMsg,(NUM_RHO_VALUES*NUM_MODELS + 1)*sizeof(float),&status,NULL) == 0)
    {
        lastError = GetLastError();
        printf("Error %d, writting data to serial port.\n",lastError);
#ifndef DBG_DATA_SEND
        return -1;
#endif
    }

#ifdef DBG_DATA_SEND
	fwrite(coeffMsg,coeffMsgSize,1,test_output);
#endif

	if(WriteFile(serialHandle,coeffMsg, coeffMsgSize,&status,NULL) == 0)
    {
        lastError = GetLastError();
        printf("Error %d, writting data to serial port.\n",lastError);
#ifndef DBG_DATA_SEND
		free(coeffMsg);
        return -1;
#endif
    }
	free(coeffMsg);
	
	return 0;

}




int closeBTComms()
{
	CloseHandle(serialHandle);
	return 0;
}
