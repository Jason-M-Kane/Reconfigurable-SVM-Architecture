/////////////////////////////////////////////////////
// GenericSVM_Tester.cpp : Test Code for SVM FPGA. //
//     This version supports 1 model, but iterates //
//     on up to 4 input files.                     //
/////////////////////////////////////////////////////
#include <time.h>
#include <stdio.h>
#include <conio.h>
#include <ctype.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <windows.h>
#include <math.h>
#include <time.h>
#include "config_Flgs.h"		//Contains parameters specific to model being used
#include "svm.h"
#include "norm_params.h"
#include "BlueToothServer.h"

/* Prototypes */
void ClearScreen (void);
void GetTextCursor (int *x, int *y);
void MoveCursor (int x, int y);

/* Globals */
struct svm_node *x;
int max_nr_attr = NUM_FEATURES*2;	//was 64
struct svm_model* model[NUM_MODELS+5];	//+5 is just to get the warning to go away if NUM_MODEL < 4
extern char modelFile[10][300];
extern char kernel_modelFile[10][300];
extern int G_CMD_SET;

/* Prototypes */
int translatePrediction(int cpu_prediction);


void exit_input_error(int line_num)
{
	fprintf(stderr,"Wrong input format at line %d\n", line_num);
	exit(1);
}

int predict(char *input, int modelNum, int *prediction)
{
	int correct = 0;
	int total = 0;
	double error = 0;
	double sump = 0, sumt = 0, sumpp = 0, sumtt = 0, sumpt = 0;

	int svm_type;
	int nr_class;

	int EOF_ = FALSE;
	double target_label, predict_label;
	char *idx, *val, *label, *endptr;
	int i = 0;

	svm_type=svm_get_svm_type(model[modelNum-1]);
	nr_class=svm_get_nr_class(model[modelNum-1]);

	label = strtok(input," \t");
	while (!EOF_)
	{
		label = strtok(NULL," \t");
		i=0;
		if(strcmp(label,"END_DATA") == 0)
		{
			EOF_ = TRUE;
			break;
		}

		target_label = strtod(label,&endptr);
		if(endptr == label)
			exit_input_error(total+1);

		while(1)
		{
			int inst_max_index = -1; // strtol gives 0 if wrong format, and precomputed kernel has <index> start from 0

			if(i >= max_nr_attr-1)	// need one more for index = -1
			{
				max_nr_attr *= 2;
				x = (struct svm_node *) realloc(x,max_nr_attr*sizeof(struct svm_node));
			}

			idx = strtok(NULL,":");
			val = strtok(NULL," \t");

			if(strcmp(idx,"END") == 0 || strcmp(idx," END") == 0)
				break;
			errno = 0;
			x[i].index = (int) strtol(idx,&endptr,10);
			if(endptr == idx || errno != 0 || *endptr != '\0' || x[i].index <= inst_max_index)
				exit_input_error(total+1);
			else
				inst_max_index = x[i].index;

			errno = 0;
			x[i].value = strtod(val,&endptr);
			if(endptr == val || errno != 0 || (*endptr != '\0' && !isspace(*endptr)))
				exit_input_error(total+1);

			++i;
		}
		x[i].index = -1;

		predict_label = svm_predict((model[modelNum-1]),x);
		*prediction = (int)predict_label;

		if(predict_label == target_label)
			++correct;
		error += (predict_label-target_label)*(predict_label-target_label);
		sump += predict_label;
		sumt += target_label;
		sumpp += predict_label*predict_label;
		sumtt += target_label*target_label;
		sumpt += predict_label*target_label;
		++total;
	}

	if (svm_type==NU_SVR || svm_type==EPSILON_SVR)
	{
		printf("Mean squared error = %g (regression)\n",error/total);
		printf("Squared correlation coefficient = %g (regression)\n",
		       ((total*sumpt-sump*sumt)*(total*sumpt-sump*sumt))/
		       ((total*sumpp-sump*sump)*(total*sumtt-sumt*sumt))
		       );
	}

	/* Return Pass/Fail for CPU Classification */
	if(predict_label == target_label)
	{
		return(TRUE);
	}
	else
	{
		return(FALSE);
	}
}




int main(int argc, char **argv)
{
	FILE *output, *testFile,*summary_outf;	//Output used for datalog; testFile used for test vector input
	int i,u,v,iter;				//Used as a counter for various loops
	char* pch;

	//Temp String Manipulation
	static char local_svm_node[240000];
	static char temp_svm_node[240000];
	static char outputFilename[300];
	static char summaryoutputFilename[300];

	//Feature Storage
	static float Feature_Data[NUM_FEATURES];

	//Prediction variables
	int testnum,numFail;
	int correct_predicts = 0;				//LIBSVM Correct Predictions
	int attempted_predicts = 0;				//LIBSVM Attempted Predictions
    int current_prediction=0;				//Current CPU Prediction
	unsigned short FPGA_Prediction = 0xff;	//Current FPGA Prediction
	int numMatch = 0;						//Number of predicitons that FPGA and CPU match for
	int run = 1;

	//Log Information
	int DataLogging=FALSE, LogSize=0, FirstPass = FALSE;
	static double Log_Channel_1_Data[300000],Log_Channel_2_Data[300000],
		Log_Channel_3_Data[300000],Log_Channel_4_Data[300000],
		Log_Channel_5_Data[300000],Log_Channel_6_Data[300000];

	//Timing Info
	LARGE_INTEGER ticksPerSecond,tick1,tick2;
	double PredictionTime=0.0, FPGA_Prediction_Time=0.0;

	//Take over the OS for better performance
	SetPriorityClass (GetCurrentProcess(),REALTIME_PRIORITY_CLASS);
	SetThreadPriority (GetCurrentThread(),THREAD_PRIORITY_TIME_CRITICAL);

	// Perform Bluetooth Initialization
	setupBluetooth();

	//Perform Model Loading for LibSVM -- This is HARD-CODED
	for(iter=0;iter<4;iter++)
	{
		/* Init */
		correct_predicts = 0;				//LIBSVM Correct Predictions
		attempted_predicts = 0;				//LIBSVM Attempted Predictions
		current_prediction=0;				//Current CPU Prediction
		FPGA_Prediction = 0xff;				//Current FPGA Prediction
		numMatch = 0;
		DataLogging=FALSE;
		LogSize=0;
		FirstPass = FALSE;
		testnum = 0;
		numFail = 0;

		memset(outputFilename,0,300);
		memset(summaryoutputFilename,0,300);

		if(iter==0)
		{
			printf("Model %s Selected.\n",FNAME_1);
			model[0] = svm_load_model(FNAME_1);
			strcpy(outputFilename,FNAME_1);
			strcpy(modelFile[0],MODEL_FNAME_1A);
			strcpy(kernel_modelFile[0],FNAME_1);
		}
		else if(iter==1)
		{
			printf("Model %s Selected.\n",FNAME_2);
			model[0] = svm_load_model(FNAME_2);
			strcpy(outputFilename,FNAME_2);
			strcpy(modelFile[0],MODEL_FNAME_2A);
			strcpy(kernel_modelFile[0],FNAME_2);
		}
		else if(iter==2)
		{
			printf("Model %s Selected.\n",FNAME_3);
			model[0] = svm_load_model(FNAME_3);
			strcpy(outputFilename,FNAME_3);
			strcpy(modelFile[0],MODEL_FNAME_3A);
			strcpy(kernel_modelFile[0],FNAME_3);
		}
		else if(iter==3)
		{
			printf("Model %s Selected.\n",FNAME_4);
			model[0] = svm_load_model(FNAME_4);
			strcpy(outputFilename,FNAME_4);
			strcpy(modelFile[0],MODEL_FNAME_4A);
			strcpy(kernel_modelFile[0],FNAME_4);
		}
		else
		{
			printf("Error, shouldnt get here. Iter = %d\n",iter);
			return -1;
		}
		x = (struct svm_node *) malloc(max_nr_attr*sizeof(struct svm_node));
		strcpy(summaryoutputFilename,outputFilename);
		strcat(summaryoutputFilename,".txt");

		// Send Models Via BlueTooth
		sendModelData();
		printf("Sent Model Data Msgs\n");

		//Wait for User Input
		printf("Enable Data Logging (Y)es or (N)o?");
		fflush(stdin);
		char inkey;
		inkey = 0x00;
		while( (inkey != 'Y') && (inkey != 'N') )
		{
			scanf("%c",&inkey);
		}
		if (inkey == 'Y')
		{
			strcat(outputFilename,"_output.csv");
			DataLogging = TRUE;
			fflush(stdin);
		}
		else if (inkey == 'N')
		{
			DataLogging = FALSE;
		}
		else
			DataLogging = FALSE;

		/* set up the display screen */
		ClearScreen();

		for (i=1;i<=NUM_MODELS;i++) //cycle through the models
		{
			testFile = fopen(TEST_FNAME,"r");
			if(testFile == NULL)
			{
				printf("Error, %s could not be located.\n",TEST_FNAME);
				continue;
			}
			summary_outf = fopen(summaryoutputFilename,"w");
			if(summary_outf == NULL)
			{
				printf("Error, %s could not be created.\n",summaryoutputFilename);
				continue;
			}
			correct_predicts=0;

			//Send Kernel Parameters via BlueTooth	
			sendKernelData(i-1);
			printf("Sent Kernel Data Msg\n");

			while((fscanf(testFile, "%[^\n]%*c", temp_svm_node)) != EOF)
			{
				testnum++;
				sprintf(local_svm_node,"START_DATA %sEND:TEST END_DATA",temp_svm_node);
				G_CMD_SET=0;

				// Have the computer make the prediction and time it.  PredictionTime stores this timing information.
				QueryPerformanceCounter(&tick1);			
				if (predict(&local_svm_node[0], i, &current_prediction) == TRUE) correct_predicts++;
				attempted_predicts++;
				QueryPerformanceCounter(&tick2);
				QueryPerformanceFrequency(&ticksPerSecond);
				PredictionTime = (double)(tick2.QuadPart-tick1.QuadPart)/(ticksPerSecond.QuadPart/1000);

				////////////////////////////
				// Read features for fpga //
				////////////////////////////
				v = 0;
				pch = strtok(temp_svm_node," :");
				while(pch != NULL)
				{
					pch = strtok(NULL," :");
					pch = strtok(NULL," :");
					sscanf(pch,"%f",&Feature_Data[v]);
					v++;
					if(v == NUM_FEATURES)
						break;
				}
				if(v != NUM_FEATURES)
				{
					printf("FILE READ ERROR!!! Should not get here\n");
					return -1;
				}

				//Sent Real Time Feature Data to the FPGA
				sendRTData(&Feature_Data[0]);
			
				//wait for FPGA Response
				recvClass(&FPGA_Prediction,&FPGA_Prediction_Time);

				/***************************************************************************/
				/* Translation Code                                                        */
				/* This code translates the computer's prediction to the FPGA's prediction */
				/* #defines in config_Flgs.h govern the behavior.                          */
				/***************************************************************************/
				current_prediction = translatePrediction(current_prediction);

				/* Check Pass/Fail Status */
				if(FPGA_Prediction != current_prediction)
				{
					printf("\nFail on test #%d.  Got %d, Exp %d\n",testnum,FPGA_Prediction,current_prediction);
					fprintf(summary_outf,"Fail on test #%d.  Got %d, Exp %d\n",testnum,FPGA_Prediction,current_prediction);
					numFail++;
				}
				else
				{
					numMatch++;
					printf("\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\bNum Match = %d\tFail = %d",numMatch,numFail);
				}

				/* Log the data for this iteration */
				if (DataLogging == TRUE && LogSize <= 299900)
				{
					Log_Channel_1_Data[LogSize] = current_prediction;	//CPU Prediction
					Log_Channel_2_Data[LogSize] = FPGA_Prediction;		//FPGA Prediction
					Log_Channel_3_Data[LogSize] = PredictionTime;		//CPU Prediction Time
					Log_Channel_4_Data[LogSize] = FPGA_Prediction_Time; //FPGA Prediction Time
					Log_Channel_5_Data[LogSize] = correct_predicts;		//LIBSVM Model Correct Predictions
					Log_Channel_6_Data[LogSize] = attempted_predicts;	//LIBSVM Model # Predictions
					LogSize++;
				}
				if (LogSize >= 299900 && FirstPass == FALSE)
				{
					printf("Log is full.  Logging STOPPED!!!\n");
					FirstPass = TRUE;
				}
			}
			printf("\nSummary of Run %d:\n"
				   "====================\n"
				   "LIBSVM: %d Correct Predictions %d Attempted Predictions (%f%%)\n"
				   "FPGA/CPU Matches: %d/%d (%f%%)\n\n", run,
					   correct_predicts,attempted_predicts,((float)correct_predicts/(float)attempted_predicts)*(float)100.0,
					   numMatch,attempted_predicts, ((float)numMatch/(float)attempted_predicts)*(float)100.0);
			fprintf(summary_outf,"\nSummary of Run %d:\n"
				   "====================\n"
				   "LIBSVM: %d Correct Predictions %d Attempted Predictions (%f%%)\n"
				   "FPGA/CPU Matches: %d/%d (%f%%)\n\n", run,
					   correct_predicts,attempted_predicts,((float)correct_predicts/(float)attempted_predicts)*(float)100.0,
					   numMatch,attempted_predicts, ((float)numMatch/(float)attempted_predicts)*(float)100.0);
			run++;
			printf("Hit enter to continue\n");
  			fflush(stdin);
			getchar();
			fclose(testFile);
			fclose(summary_outf);
		}

		if (DataLogging == TRUE)
		{
			printf("Storing Data Log...\n");
			output = fopen(outputFilename,"w");
			if (output == NULL)
			{
				printf("Log File Open Failed\n");
			}
			else
			{
				for (i=0;i<LogSize;i++) 
				{
					fprintf(output,"%.15f",Log_Channel_1_Data[i]);
					fprintf(output,",");
					fprintf(output,"%.15f",Log_Channel_2_Data[i]);
					fprintf(output,",");
					fprintf(output,"%.15f",Log_Channel_3_Data[i]);
					fprintf(output,",");
					fprintf(output,"%.15f",Log_Channel_4_Data[i]);
					fprintf(output,",");
					fprintf(output,"%.15f",Log_Channel_5_Data[i]);
					fprintf(output,",");
					fprintf(output,"%.15f",Log_Channel_6_Data[i]);
					fprintf(output,"\n");
				}
			}//End Else from If Open Failed 
			fclose(output);
		}

		//Free the LIBSVM Models
		for(u = 0; u < NUM_MODELS; u++)
		{
			svm_free_and_destroy_model(&model[u]);
		}
		free(x);
		x = NULL;

		printf ("LogSize = %i.\n",LogSize);
		printf ("Data collection terminated.  Hit enter to continue.\n");
		fflush(stdin);
		getchar();

#ifdef HAND_MODEL
		break;
#endif

	}
	closeBTComms();

	return 0;
}




/***************************************************************************/
/* Translation Code                                                        */
/* This code translates the computer's prediction to the FPGA's prediction */
/* #defines in config_Flgs.h govern the behavior.                          */
/***************************************************************************/
int translatePrediction(int cpu_prediction)
{
	int translation = 999;

	//KANE - FIX cpu Predictions to match the fpga
#ifdef LETTER_MODEL
	if(cpu_prediction == 26)
		translation = 1;
	else if(cpu_prediction == 16)
		translation = 2;
	else if(cpu_prediction == 19)
		translation = 3;
	else if(cpu_prediction == 8)
		translation = 4;
	else if(cpu_prediction == 6)
		translation = 5;
	else if(cpu_prediction == 14)
		translation = 6;
	else if(cpu_prediction == 18)
		translation = 7;
	else if(cpu_prediction == 13)
		translation = 8;
	else if(cpu_prediction == 4)
		translation = 9;
	else if(cpu_prediction == 22)
		translation = 10;
	else if(cpu_prediction == 1)
		translation = 11;
	else if(cpu_prediction == 11)
		translation = 12;
	else if(cpu_prediction == 5)
		translation = 13;
	else if(cpu_prediction == 15)
		translation = 14;
	else if(cpu_prediction == 17)
		translation = 15;
	else if(cpu_prediction == 12)
		translation = 16;
	else if(cpu_prediction == 24)
		translation = 17;
	else if(cpu_prediction == 25)
		translation = 18;
	else if(cpu_prediction == 9)
		translation = 19;
	else if(cpu_prediction == 23)
		translation = 20;
	else if(cpu_prediction == 21)
		translation = 21;
	else if(cpu_prediction == 20)
		translation = 22;
	else if(cpu_prediction == 3)
		translation = 23;
	else if(cpu_prediction == 7)
		translation = 24;
	else if(cpu_prediction == 2)
		translation = 25;
	else if(cpu_prediction == 10)
		translation = 26;
#endif

#ifdef DNA_MODEL
	/* 3 1 2 */
	if(cpu_prediction == 3)
		translation = 1;
	else if(cpu_prediction == 1)
		translation = 2;
	else if(cpu_prediction == 2)
		translation = 3;
#endif

#ifdef SAT_MODEL
		
	translation = cpu_prediction;
#endif

#ifdef SHUTTLE_MODEL
		
	if(cpu_prediction == 2)
		translation = 1;
	else if(cpu_prediction == 4)
		translation = 2;
	else if(cpu_prediction == 1)
		translation = 3;
	else if(cpu_prediction == 5)
		translation = 4;
	else if(cpu_prediction == 3)
		translation = 5;
	else if(cpu_prediction == 7)
		translation = 6;
	else if(cpu_prediction == 6)
		translation = 7;
#endif

#ifdef VOWEL_MODEL
	translation = cpu_prediction+1;
#endif

#ifdef ADULT_MODEL
	if(cpu_prediction == 1)
		translation = 2;
	else if(cpu_prediction == -1)
		translation = 1;
	else
		translation = 3;
#endif

#ifdef HAND_MODEL
	translation = cpu_prediction;
#endif

	return translation;
}




/******************************************************************/
/***********************DATA ACQUISITION FUNCTIONS*****************/
/******************************************************************/

/***************************************************************************
*
* Name:      ClearScreen
* Arguments: ---
* Returns:   ---
*
* Clears the screen.
*
***************************************************************************/

#define BIOS_VIDEO   0x10
void ClearScreen (void)
{
	COORD coordOrg = {0, 0};
	DWORD dwWritten = 0;
	HANDLE hConsole = GetStdHandle(STD_OUTPUT_HANDLE);

	FillConsoleOutputCharacter(hConsole, ' ', 50 * 300, coordOrg, &dwWritten);
	MoveCursor(0, 0);

    return;
}




/***************************************************************************
*
* Name:      MoveCursor
* Arguments: x,y - screen coordinates of new cursor position
* Returns:   ---
*
* Positions the cursor on screen.
*
***************************************************************************/
void MoveCursor (int x, int y)
{
	HANDLE hConsole = GetStdHandle(STD_OUTPUT_HANDLE);

	if (INVALID_HANDLE_VALUE != hConsole)
	{
		COORD coordCursor;
		coordCursor.X = (short)x;
		coordCursor.Y = (short)y;
		SetConsoleCursorPosition(hConsole, coordCursor);
	}

    return;
}





/***************************************************************************
*
* Name:      GetTextCursor
* Arguments: x,y - screen coordinates of new cursor position
* Returns:   *x and *y
*
* Returns the current (text) cursor position.
*
***************************************************************************/
void GetTextCursor (int *x, int *y)
{
	HANDLE hConsole = GetStdHandle(STD_OUTPUT_HANDLE);
	CONSOLE_SCREEN_BUFFER_INFO csbi;

	*x = -1;
	*y = -1;
	if (INVALID_HANDLE_VALUE != hConsole)
	{
		GetConsoleScreenBufferInfo(hConsole, &csbi);
		*x = csbi.dwCursorPosition.X;
		*y = csbi.dwCursorPosition.Y;
	}

    return;
}
