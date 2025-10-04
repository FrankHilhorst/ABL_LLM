/*------------------------------------------------------------------------------
    File: LayerSharedDefs.i
    Purpose: Shared constants and structures used across all LLM layers
------------------------------------------------------------------------------*/

/* === CONFIGURABLE CONSTANTS === */ 
/************************************************************
//&GLOBAL-DEFINE EMBEDDING_SIZE 768        /* Dimensionality of token embeddings */
//&GLOBAL-DEFINE VOCAB_SIZE     10000      /* Vocabulary size (can be reduced for prototyping) */
//&GLOBAL-DEFINE MAX_SEQUENCE_LENGTH 512 
//&GLOBAL-DEFINE FF_DIM 3072               /* 768 * 4 */ 
//&GLOBAL-DEFINE E 2.7182818
//&GLOBAL-DEFINE PredictionWindowSise 4
************************************************************/

&GLOBAL-DEFINE EMBEDDING_SIZE        16       /* Small vector size sufficient for symbolic tokens */
&GLOBAL-DEFINE VOCAB_SIZE            13       /* 0–9, +, -, = (optionally [EOS]) */
&GLOBAL-DEFINE MAX_SEQUENCE_LENGTH   12        /* e.g., "2 + 3 =" ? "5", total 6 tokens */
&GLOBAL-DEFINE FF_DIM                32       /* 2× embedding size: adds non-linearity capacity */
&GLOBAL-DEFINE E                     2.7182818 /* Keep as is for any exponential ops */
&GLOBAL-DEFINE PredictionWindowSize 1         /* Predict only 1 token at a time, like "5" */
&GLOBAL-DEFINE LAYERARCHITECTURE "EMB,POS,RES,ATT,RES,NORM,RES,FF,RES,NORM,LOG,OUT"
&GLOBAL-DEFINE DictTokens "0,1,2,3,4,5,6,7,8,9, ,+,-,=,~~n"

    /* Define constants */

/* === SHARED TEMP-TABLE STRUCTURE === */
/* Used to pass embeddings forward and backward between layers */
DEFINE TEMP-TABLE ttContextEmbedding NO-UNDO
    FIELD PosNo   AS INTEGER                              /* Position in sequence */
    FIELD TokenId AS INTEGER                              /* Token identity */
    FIELD Weight  AS DECIMAL EXTENT {&EMBEDDING_SIZE}     /* Embedding vector */
    FIELD reluWeight AS DEC EXTENT {&FF_DIM}
    FIELD HiddenPreActivation AS DECIMAL EXTENT {&FF_DIM}
    FIELD GradLogit AS DECIMAL EXTENT {&VOCAB_SIZE}
    FIELD Probabilities AS DECIMAL EXTENT {&VOCAB_SIZE}.
    
DEFINE TEMP-TABLE ttPersistedContextEmbedding NO-UNDO SERIALIZE-NAME "ttContextEmbedding" LIKE ttContextEmbedding.
    
