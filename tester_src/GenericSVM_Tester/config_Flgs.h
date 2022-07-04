#ifndef CONFIG_FLGS_H
#define CONFIG_FLGS_H

#pragma warning (disable: 4996)
#pragma comment(lib, "wsock32.lib")

#define TRUE 1
#define FALSE 0

/* FPGA Parameters, only edit if i change the FPGA frequency */
#define FPGA_CLOCK_FREQ_MHZ		(double)(60.0)

/* COM PORT, Change if computer is using a different one */
#define COM_PORT_TO_USE					"COM3"

/*******************************************************************************/
/* MODEL Selection, Also selects CPU Prediction to FPGA Prediction Translation */
/*		!!! Edit ME TO SELECT THE RIGHT MODEL !!!							   */
/*******************************************************************************/
#define ADULT_MODEL
//#define HAND_MODEL
//#define LETTER_MODEL
//#define DNA_MODEL
//#define SAT_MODEL
//#define SHUTTLE_MODEL
//#define VOWEL_MODEL



/*************************************************************/
/* Classification Parameters, fix these if i have them wrong */
/*************************************************************/
#ifdef ADULT_MODEL
	#define NUM_MODELS				1
	#define NUM_FEATURES			123
	#define NUM_CLASS				3

	/* Test Filename */
	#define TEST_FNAME						"Model_Data\\Adult\\a1a_fixed.t"

	/* Default Model File Names (Up to 1st 4, otherwise code edit required) */
	/* If there are less than 4 models, dont worry about the extra filenames*/
	#define FNAME_1							"Model_Data\\Adult\\a1a_fixed.lin.model"
	#define FNAME_2							"Model_Data\\Adult\\a1a_fixed.poly.model"
	#define FNAME_3							"Model_Data\\Adult\\a1a_fixed.rbf.model"
	#define FNAME_4							"Model_Data\\Adult\\a1a_fixed.sig.model"
	#define MODEL_FNAME_1A					"Model_Data\\Adult\\a1a_fixed.linA.model"
	#define MODEL_FNAME_2A					"Model_Data\\Adult\\a1a_fixed.polyA.model"
	#define MODEL_FNAME_3A					"Model_Data\\Adult\\a1a_fixed.rbfA.model"
	#define MODEL_FNAME_4A					"Model_Data\\Adult\\a1a_fixed.sigA.model"
#endif

#ifdef HAND_MODEL   //84,87,94
	#define NUM_MODELS				1
	#define NUM_FEATURES			20
	#define NUM_CLASS				7
#if 0
	/* Test Filename */
	#define TEST_FNAME						"Model_Data\\Hand\\NormedFeatures84.t"

	/* Default Model File Names (Up to 1st 4, otherwise code edit required) */
	/* If there are less than 4 models, dont worry about the extra filenames*/
	#define FNAME_1							"Model_Data\\Hand\\phase1.model.84"
	#define FNAME_2							"Model_Data\\Hand\\phase1.model.84"
	#define FNAME_3							"Model_Data\\Hand\\phase1.model.84"
	#define FNAME_4							"Model_Data\\Hand\\phase1.model.84"
	#define MODEL_FNAME_1A					"Model_Data\\Hand\\phase1.modelA.84"
	#define MODEL_FNAME_2A					"Model_Data\\Hand\\phase1.modelA.84"
	#define MODEL_FNAME_3A					"Model_Data\\Hand\\phase1.modelA.84"
	#define MODEL_FNAME_4A					"Model_Data\\Hand\\phase1.modelA.84"
#endif
#if 0
	#define TEST_FNAME						"Model_Data\\Hand\\NormedFeatures87.t"

	/* Default Model File Names (Up to 1st 4, otherwise code edit required) */
	/* If there are less than 4 models, dont worry about the extra filenames*/
	#define FNAME_1							"Model_Data\\Hand\\phase1.model.87"
	#define FNAME_2							"Model_Data\\Hand\\phase1.model.87"
	#define FNAME_3							"Model_Data\\Hand\\phase1.model.87"
	#define FNAME_4							"Model_Data\\Hand\\phase1.model.87"
	#define MODEL_FNAME_1A					"Model_Data\\Hand\\phase1.modelA.87"
	#define MODEL_FNAME_2A					"Model_Data\\Hand\\phase1.modelA.87"
	#define MODEL_FNAME_3A					"Model_Data\\Hand\\phase1.modelA.87"
	#define MODEL_FNAME_4A					"Model_Data\\Hand\\phase1.modelA.87"
#endif
#if 1
	#define TEST_FNAME						"Model_Data\\Hand\\NormedFeatures94.t"

	/* Default Model File Names (Up to 1st 4, otherwise code edit required) */
	/* If there are less than 4 models, dont worry about the extra filenames*/
	#define FNAME_1							"Model_Data\\Hand\\phase1.model.94"
	#define FNAME_2							"Model_Data\\Hand\\phase1.model.94"
	#define FNAME_3							"Model_Data\\Hand\\phase1.model.94"
	#define FNAME_4							"Model_Data\\Hand\\phase1.model.94"
	#define MODEL_FNAME_1A					"Model_Data\\Hand\\phase1.modelA.94"
	#define MODEL_FNAME_2A					"Model_Data\\Hand\\phase1.modelA.94"
	#define MODEL_FNAME_3A					"Model_Data\\Hand\\phase1.modelA.94"
	#define MODEL_FNAME_4A					"Model_Data\\Hand\\phase1.modelA.94"
#endif



#endif

#ifdef LETTER_MODEL
	#define NUM_MODELS				1
	#define NUM_FEATURES			16
	#define NUM_CLASS				26

	/* Test Filename */
	#define TEST_FNAME						"Model_Data\\Letter\\letter.scale.t"

	/* Default Model File Names (Up to 1st 4, otherwise code edit required) */
	/* If there are less than 4 models, dont worry about the extra filenames*/
	#define FNAME_1							"Model_Data\\Letter\\letter.lin.model"
	#define FNAME_2							"Model_Data\\Letter\\letter.poly.model"
	#define FNAME_3							"Model_Data\\Letter\\letter.rbf.model"
	#define FNAME_4							"Model_Data\\Letter\\letter.sig.model"
	#define MODEL_FNAME_1A					"Model_Data\\Letter\\letter.linA.model"
	#define MODEL_FNAME_2A					"Model_Data\\Letter\\letter.polyA.model"
	#define MODEL_FNAME_3A					"Model_Data\\Letter\\letter.rbfA.model"
	#define MODEL_FNAME_4A					"Model_Data\\Letter\\letter.sigA.model"
#endif

#ifdef DNA_MODEL
	#define NUM_MODELS				1
	#define NUM_FEATURES			180
	#define NUM_CLASS				3

	/* Test Filename */
	#define TEST_FNAME						"Model_Data\\Dna\\dna.scale.t"

	/* Default Model File Names (Up to 1st 4, otherwise code edit required) */
	/* If there are less than 4 models, dont worry about the extra filenames*/
	#define FNAME_1							"Model_Data\\Dna\\dna.lin.model"
	#define FNAME_2							"Model_Data\\Dna\\dna.poly.model"
	#define FNAME_3							"Model_Data\\Dna\\dna.rbf.model"
	#define FNAME_4							"Model_Data\\Dna\\dna.sig.model"
	#define MODEL_FNAME_1A					"Model_Data\\Dna\\dna.linA.model"
	#define MODEL_FNAME_2A					"Model_Data\\Dna\\dna.polyA.model"
	#define MODEL_FNAME_3A					"Model_Data\\Dna\\dna.rbfA.model"
	#define MODEL_FNAME_4A					"Model_Data\\Dna\\dna.sigA.model"
#endif

#ifdef SAT_MODEL
	#define NUM_MODELS				1
	#define NUM_FEATURES			36
	#define NUM_CLASS				6

	/* Test Filename */
	#define TEST_FNAME						"Model_Data\\SatImage\\satimage.scale.t"

	/* Default Model File Names (Up to 1st 4, otherwise code edit required) */
	/* If there are less than 4 models, dont worry about the extra filenames*/
	#define FNAME_1							"Model_Data\\SatImage\\satimage.lin.model"
	#define FNAME_2							"Model_Data\\SatImage\\satimage.poly.model"
	#define FNAME_3							"Model_Data\\SatImage\\satimage.rbf.model"
	#define FNAME_4							"Model_Data\\SatImage\\satimage.sig.model"
	#define MODEL_FNAME_1A					"Model_Data\\SatImage\\satimage.linA.model"
	#define MODEL_FNAME_2A					"Model_Data\\SatImage\\satimage.polyA.model"
	#define MODEL_FNAME_3A					"Model_Data\\SatImage\\satimage.rbfA.model"
	#define MODEL_FNAME_4A					"Model_Data\\SatImage\\satimage.sigA.model"
#endif

#ifdef SHUTTLE_MODEL
	#define NUM_MODELS				1
	#define NUM_FEATURES			9
	#define NUM_CLASS				7

	/* Test Filename */
	#define TEST_FNAME						"Model_Data\\Shuttle\\shuttle.scale.t"

	/* Default Model File Names (Up to 1st 4, otherwise code edit required) */
	/* If there are less than 4 models, dont worry about the extra filenames*/
	#define FNAME_1							"Model_Data\\Shuttle\\shuttle.lin.model"
	#define FNAME_2							"Model_Data\\Shuttle\\shuttle.poly.model"
	#define FNAME_3							"Model_Data\\Shuttle\\shuttle.rbf.model"
	#define FNAME_4							"Model_Data\\Shuttle\\shuttle.sig.model"
	#define MODEL_FNAME_1A					"Model_Data\\Shuttle\\shuttle.linA.model"
	#define MODEL_FNAME_2A					"Model_Data\\Shuttle\\shuttle.polyA.model"
	#define MODEL_FNAME_3A					"Model_Data\\Shuttle\\shuttle.rbfA.model"
	#define MODEL_FNAME_4A					"Model_Data\\Shuttle\\shuttle.sigA.model"
#endif

#ifdef VOWEL_MODEL
	#define NUM_MODELS				1
	#define NUM_FEATURES			10
	#define NUM_CLASS				11

	/* Test Filename */
	#define TEST_FNAME						"Model_Data\\Vowel\\vowel.scale.t"

	/* Default Model File Names (Up to 1st 4, otherwise code edit required) */
	/* If there are less than 4 models, dont worry about the extra filenames*/
	#define FNAME_1							"Model_Data\\Vowel\\vowel.lin.model"
	#define FNAME_2							"Model_Data\\Vowel\\vowel.poly.model"
	#define FNAME_3							"Model_Data\\Vowel\\vowel.rbf.model"
	#define FNAME_4							"Model_Data\\Vowel\\vowel.sig.model"
	#define MODEL_FNAME_1A					"Model_Data\\Vowel\\vowel.linA.model"
	#define MODEL_FNAME_2A					"Model_Data\\Vowel\\vowel.polyA.model"
	#define MODEL_FNAME_3A					"Model_Data\\Vowel\\vowel.rbfA.model"
	#define MODEL_FNAME_4A					"Model_Data\\Vowel\\vowel.sigA.model"
#endif





#endif
