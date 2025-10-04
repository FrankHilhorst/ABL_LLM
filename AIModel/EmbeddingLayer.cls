USING Progress.Lang.*.
USING Progress.Json.ObjectModel.*.
USING AIModel.Layer.

CLASS AIModel.EmbeddingLayer INHERITS Layer:

    {AIModel/LayerSharedDefs.i}

    DEFINE VARIABLE hTrace AS HANDLE      NO-UNDO.

    DEFINE TEMP-TABLE ttContextEmbeddingTemp NO-UNDO SERIALIZE-NAME "ttContextEmbedding" LIKE ttContextEmbedding .     
    
    DEFINE TEMP-TABLE ttTargetEmbeddingsDictionary NO-UNDO LIKE ttEmbeddingsDictionary.

        /* Number of unique tokens in the vocabulary */
    DEFINE PRIVATE VARIABLE vocabSize AS INTEGER NO-UNDO.
    
    /* Constructor */
    CONSTRUCTOR PUBLIC EmbeddingLayer(iLayerNo AS INT,iLayerCode AS CHAR, ihCallingProc AS HANDLE):  
        SUPER(iLayerNo,iLayerCode,ihCallingProc). 
        ASSIGN THIS-OBJECT:vocabSize = {&VOCAB_SIZE}.
    END CONSTRUCTOR.

    /* Initializes the embedding dictionary with random values */
    METHOD PUBLIC OVERRIDE VOID initializeWeights():
        DEFINE VARIABLE iToken  AS INTEGER NO-UNDO.
        DEFINE VARIABLE i       AS INTEGER NO-UNDO.
        DEFINE VARIABLE randVal AS DECIMAL NO-UNDO.
        DEFINE VARIABLE DictTokens AS CHARACTER   NO-UNDO.

        DictTokens = {&DictTokens}.
        DO iToken = 1 TO NUM-ENTRIES(DictTokens):
            CREATE ttEmbeddingsDictionary.
            ASSIGN
                ttEmbeddingsDictionary.TokenId = iToken
                ttEmbeddingsDictionary.cToken  = ENTRY(iToken,DictTokens).
            DO i = 1 TO EXTENT(ttEmbeddingsDictionary.Weight):
                randVal = (RANDOM(0,1000) / 1000) * 0.02 - 0.01. /* [-0.01, 0.01] */
                ttEmbeddingsDictionary.Weight[i] = randVal.
            END.
        END.
    END METHOD.
    
    METHOD PUBLIC OVERRIDE JsonObject serialize():
        DEFINE VARIABLE oJson   AS JsonObject NO-UNDO.
        DEFINE VARIABLE lcJson  AS LONGCHAR   NO-UNDO.

        oJson = NEW JsonObject().
        TEMP-TABLE ttEmbeddingsDictionary:WRITE-JSON("JSONOBJECT", oJson, TRUE).
        RETURN oJson.
    END METHOD.
    
    METHOD PUBLIC OVERRIDE VOID deserialize(INPUT oJson AS JsonObject):
        TEMP-TABLE ttEmbeddingsDictionary:READ-JSON("JsonObject", oJson, "empty").
    END METHOD.
    
    /* The forward method */
     METHOD PUBLIC OVERRIDE LONGCHAR forward(INPUT exampleStr AS LONGCHAR):
        DEFINE VARIABLE iToken     AS INTEGER     NO-UNDO.
        DEFINE VARIABLE tokens     AS CHARACTER   NO-UNDO EXTENT.
        DEFINE VARIABLE i          AS INTEGER     NO-UNDO.
        DEFINE VARIABLE lcJson     AS LONGCHAR    NO-UNDO.
        DEFINE VARIABLE tokenList  AS CHARACTER   NO-UNDO.

        /* Clear the output table */
        EMPTY TEMP-TABLE ttContextEmbedding.
        EMPTY TEMP-TABLE ttContextEmbeddingTemp.

        ASSIGN tokenList = THIS-OBJECT:getTokenList(STRING(exampleStr)).
        
        /* Token list is a comma-separated list of token IDs */
        DO i = 1 TO NUM-ENTRIES(tokenList):
            iToken = INTEGER(ENTRY(i, tokenList)).

            FIND FIRST ttEmbeddingsDictionary 
                WHERE ttEmbeddingsDictionary.TokenId = iToken 
                NO-LOCK NO-ERROR.

            IF AVAILABLE ttEmbeddingsDictionary THEN DO:
                CREATE ttContextEmbedding.
                ASSIGN
                    ttContextEmbedding.PosNo   = i
                    ttContextEmbedding.TokenId = iToken
                    ttContextEmbedding.Weight  = ttEmbeddingsDictionary.Weight.
            END.
        END.

        THIS-OBJECT:cloneContextEmbedding(BUFFER ttContextEmbedding:HANDLE,BUFFER ttPersistedContextEmbedding:HANDLE).
        TEMP-TABLE ttContextEmbedding:WRITE-JSON("LONGCHAR", lcJson, TRUE).

TEMP-TABLE ttContextEmbeddingTemp:WRITE-JSON("file",SUBST("c:\temp\ttContextEmbeddingTemp_F_&1_&2.json",
                                                           THIS-OBJECT:LayerCode,THIS-OBJECT:LayerNo), TRUE).
             
        PUBLISH "browseRefresh" FROM CallingProc (INPUT THIS-OBJECT:LayerNo).     
        RETURN lcJson.
    END METHOD.

    METHOD PUBLIC OVERRIDE LONGCHAR backward(INPUT lcGradOutput AS LONGCHAR):
        DEFINE VARIABLE lcOutput     AS LONGCHAR NO-UNDO.
        DEFINE VARIABLE i            AS INTEGER  NO-UNDO.
        DEFINE VARIABLE k            AS INTEGER  NO-UNDO.
//      DEFINE VARIABLE learningRate AS DECIMAL  NO-UNDO INITIAL 0.01.
        DEFINE VARIABLE diff         AS DECIMAL  NO-UNDO.

        DEFINE BUFFER ttCorrected       FOR ttContextEmbeddingTemp.
        DEFINE BUFFER ttOriginal        FOR ttPersistedContextEmbedding.
        DEFINE BUFFER ttEmbeddingDict   FOR ttEmbeddingsDictionary.

        EMPTY TEMP-TABLE ttContextEmbeddingTemp.
        /* Load corrected embeddings (from next layer’s backward) */
        TEMP-TABLE ttContextEmbeddingTemp:READ-JSON("LONGCHAR", lcGradOutput, "empty").

        /* Loop over each token and adjust its corresponding embedding */
        FOR EACH ttCorrected NO-LOCK:

            /* Find the original embedding we passed to the next layer */
            FIND FIRST ttOriginal WHERE ttOriginal.PosNo = ttCorrected.PosNo NO-LOCK NO-ERROR.
            IF NOT AVAILABLE ttOriginal THEN NEXT.

            /* Locate the learned vector in the embedding dictionary */
            FIND FIRST ttEmbeddingDict WHERE ttEmbeddingDict.TokenId = ttCorrected.TokenId EXCLUSIVE-LOCK NO-ERROR.
            IF NOT AVAILABLE ttEmbeddingDict THEN NEXT.

            /* Adjust the embedding dictionary using gradient descent */
            DO i = 1 TO {&EMBEDDING_SIZE}:
                /* Gradient: difference between what it was and what it should be */
                diff = ttCorrected.Weight[i] - ttOriginal.Weight[i].

                /* Gradient descent update */
                ttEmbeddingDict.Weight[i] = ttEmbeddingDict.Weight[i] + THIS-OBJECT:LearningRate * diff.
            END.
        END.

        PUBLISH "browseRefresh" FROM CallingProc (INPUT THIS-OBJECT:LayerNo).
        /* Return corrected snapshot as output to prior layer */
        TEMP-TABLE ttPersistedContextEmbedding:WRITE-JSON("LONGCHAR", lcOutput, TRUE).
        RETURN lcOutput.
    END METHOD.
    
    METHOD PRIVATE CHARACTER getTokenList(INPUT inputText AS CHARACTER):
        DEFINE VARIABLE DictTokens AS CHARACTER NO-UNDO.
        DEFINE VARIABLE iChar      AS INTEGER   NO-UNDO.
        DEFINE VARIABLE cChar      AS CHARACTER NO-UNDO.
        DEFINE VARIABLE iToken     AS INTEGER   NO-UNDO.
        DEFINE VARIABLE cTokenList AS CHARACTER NO-UNDO.

        DictTokens = {&DictTokens}.  /* e.g., "0,1,2,3,4,5,6,7,8,9, ,+,-,~~n" */

        DO iChar = 1 TO LENGTH(inputText):
            cChar = SUBSTRING(inputText, iChar, 1).
            FIND ttEmbeddingsDictionary WHERE ttEmbeddingsDictionary.cToken = cChar NO-ERROR.
            IF NOT AVAIL ttEmbeddingsDictionary THEN
                UNDO, THROW NEW AppError(SUBST("Token '&1 (&2)' not found in dictionary.",cChar,ASC(cChar)),-1).
            iToken = ttEmbeddingsDictionary.tokenId.
            IF iToken = 0 THEN 
                UNDO, THROW NEW AppError(SUBSTITUTE("Unknown token: '&1'", cChar), -1).
            cTokenList = cTokenList + (IF cTokenList = "" THEN "" ELSE ",") + STRING(iToken).
        END.

        RETURN cTokenList.
    END METHOD.
    
    METHOD PUBLIC VOID passItEmbeddingsDictionary (OUTPUT TABLE ttEmbeddingsDictionary):
    
    END METHOD.

    METHOD PUBLIC OVERRIDE VOID instantiateTracer ():
        RUN AiModel/ShowDataGrid.p PERSISTENT SET hTrace(INPUT THIS-OBJECT:LayerNo, INPUT THIS-OBJECT:LayerCode, INPUT BUFFER ttEmbeddingsDictionary:HANDLE). 
    END METHOD.

    
        
END CLASS.
