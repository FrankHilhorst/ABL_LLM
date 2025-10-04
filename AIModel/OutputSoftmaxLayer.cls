USING Progress.Lang.*.
USING Progress.Json.ObjectModel.*.
USING AIModel.Layer.
USING AIModel.*.

CLASS AIModel.OutputSoftmaxLayer INHERITS Layer:

    {AIModel/LayerSharedDefs.i}
    //DEFINE VARIABLE LearningRate AS DECIMAL     NO-UNDO INIT 0.01.    
    DEFINE TEMP-TABLE ttContextEmbeddingTemp NO-UNDO SERIALIZE-NAME "ttContextEmbedding" LIKE ttContextEmbedding.
    
    DEFINE PUBLIC PROPERTY oLogitsLayer AS LogitsLayer GET. SET.
    DEFINE PUBLIC PROPERTY oEmbeddingLayer AS EmbeddingLayer GET. SET.
    
    /* This temp-table is passed in: the true next token IDs */
         
    CONSTRUCTOR PUBLIC OutputSoftmaxLayer(iLayerNo AS INT,iLayerCode AS CHAR, ihCallingProc AS HANDLE):  
        SUPER(iLayerNo,iLayerCode,ihCallingProc).
    END CONSTRUCTOR.
 
    /* No weights to initialize for softmax */
    METHOD PUBLIC OVERRIDE VOID initializeWeights():
    END METHOD.
    
    METHOD PUBLIC OVERRIDE LONGCHAR Forward(INPUT lcInput AS LONGCHAR):
        DEFINE VARIABLE i        AS INTEGER  NO-UNDO.
        DEFINE VARIABLE j        AS INTEGER  NO-UNDO.
        DEFINE VARIABLE sumExp   AS DECIMAL  NO-UNDO.
        DEFINE VARIABLE maxLogit AS DECIMAL  NO-UNDO.
        DEFINE VARIABLE logits   AS DECIMAL EXTENT {&VOCAB_SIZE} NO-UNDO.
        DEFINE VARIABLE probs    AS DECIMAL EXTENT {&VOCAB_SIZE} NO-UNDO.
        DEFINE VARIABLE lcOut    AS LONGCHAR NO-UNDO.

        EMPTY TEMP-TABLE ttContextEmbeddingTemp.
        TEMP-TABLE ttContextEmbeddingTemp:READ-JSON("longchar", lcInput, "empty").

        THIS-OBJECT:oLogitsLayer:passTtLogits( OUTPUT TABLE ttLogits). 
TEMP-TABLE ttLogits:WRITE-JSON("file","C:\temp\ttLogits_out_start.json",TRUE).

        FOR EACH ttContextEmbeddingTemp:
            FIND FIRST ttLogits WHERE ttLogits.PosNo = ttContextEmbeddingTemp.PosNo NO-ERROR.
            IF NOT AVAIL ttLogits THEN NEXT.

            ASSIGN
                sumExp   = 0
                maxLogit = ttLogits.Logits[1].

            /* Find max logit for numerical stability */
            DO i = 2 TO {&VOCAB_SIZE}:
                IF ttLogits.Logits[i] > maxLogit THEN
                    maxLogit = ttLogits.Logits[i].
            END.

            /* Compute exp(logit - maxLogit) */
            DO i = 1 TO {&VOCAB_SIZE}:
                logits[i] = EXP({&E},ttLogits.Logits[i] - maxLogit).
                sumExp = sumExp + logits[i].
            END.

            /* Normalize to probabilities */
            DO i = 1 TO {&VOCAB_SIZE}:
                probs[i] = logits[i] / sumExp.
                ttContextEmbeddingTemp.Probabilities[i] = probs[i].
            END.
        END.

        TEMP-TABLE ttContextEmbeddingTemp:WRITE-JSON("longchar", lcOut, TRUE).

TEMP-TABLE ttContextEmbeddingTemp:WRITE-JSON("file",SUBST("c:\temp\ttContextEmbeddingTemp_F_&1_&2.json",
                                                           THIS-OBJECT:LayerCode,THIS-OBJECT:LayerNo), TRUE).
                                                           
        RETURN lcOut.
    END METHOD.
  
    METHOD PUBLIC OVERRIDE LONGCHAR Backward(INPUT lcInput AS LONGCHAR):
        DEFINE VARIABLE i        AS INTEGER     NO-UNDO.
        DEFINE VARIABLE j        AS INTEGER     NO-UNDO.
        DEFINE VARIABLE lcOutput AS LONGCHAR    NO-UNDO.

        EMPTY TEMP-TABLE ttContextEmbeddingTemp.
        TEMP-TABLE ttContextEmbeddingTemp:READ-JSON("longchar", lcInput, "empty").

        FOR EACH ttContextEmbeddingTemp:
            /* Get matching input embedding from forward pass */
            FIND FIRST ttPersistedContextEmbedding WHERE
                ttPersistedContextEmbedding.PosNo = ttContextEmbeddingTemp.PosNo NO-ERROR.
            IF NOT AVAIL ttPersistedContextEmbedding THEN NEXT.

            /* Initialize embedding gradient (Weight[]) to 0 */
            DO j = 1 TO {&EMBEDDING_SIZE}:
                ttContextEmbeddingTemp.Weight[j] = 0.
            END.

            /* Backpropagate gradients via dot-product */
            DO i = 1 TO {&VOCAB_SIZE}:
                FIND ttLogitsWeights WHERE TRUE NO-LOCK NO-ERROR.
                IF NOT AVAIL ttLogitsWeights THEN NEXT.

                DO j = 1 TO {&EMBEDDING_SIZE}:
                    ttContextEmbeddingTemp.Weight[j] = ttContextEmbeddingTemp.Weight[j]
                        + ttContextEmbeddingTemp.GradLogit[i] * ttLogitsWeights.VocabWeights[i].
                END.
            END.
        END.

        TEMP-TABLE ttContextEmbeddingTemp:WRITE-JSON("longchar", lcOutput, TRUE).
        RETURN lcOutput.
    END METHOD.
    
    METHOD PUBLIC CHARACTER getPredictions(INPUT cTargetTokenIds AS CHARACTER):
          DEFINE VARIABLE iTargetCount    AS INTEGER   NO-UNDO.
          DEFINE VARIABLE i               AS INTEGER   NO-UNDO.
          DEFINE VARIABLE j               AS INTEGER   NO-UNDO.
          DEFINE VARIABLE iStartPos       AS INTEGER   NO-UNDO.
          DEFINE VARIABLE iPos            AS INTEGER   NO-UNDO.
          DEFINE VARIABLE iTargetTokenId  AS INTEGER   NO-UNDO.
          DEFINE VARIABLE cPredictions    AS CHARACTER NO-UNDO.
          DEFINE VARIABLE dProbability    AS DECIMAL   NO-UNDO.
          DEFINE VARIABLE iPredictedId    AS INTEGER   NO-UNDO.
          
        iTargetCount = LENGTH(cTargetTokenIds).
       /* Defensive: Ensure we have at least that many positions in ttContextEmbeddingTemp */
        FIND LAST ttContextEmbeddingTemp NO-ERROR.
        IF NOT AVAILABLE ttContextEmbeddingTemp OR ttContextEmbeddingTemp.PosNo < iTargetCount THEN
            RETURN "ERROR: Not enough rows in ttContextEmbeddingTemp for training targets.".

        EMPTY TEMP-TABLE ttEmbeddingsDictionary.    
        IF NOT VALID-OBJECT(THIS-OBJECT:oEmbeddingLayer) THEN
           UNDO, THROW NEW PROGRESS.LANG.APPERROR("oEmbeddingLayer attribute not set in OutputSoftmaxLayer",-1). 
        THIS-OBJECT:oEmbeddingLayer:passItEmbeddingsDictionary(OUTPUT TABLE ttEmbeddingsDictionary).    
        iStartPos = ttContextEmbeddingTemp.PosNo - iTargetCount + 1.
//MESSAGE "iTargetCount" iTargetCount SKIP
//        "iStartPos" iStartPos SKIP
// VIEW-AS ALERT-BOX INFORMATION BUTTONS OK.
        DO i = 1 TO iTargetCount:
            iPos = iStartPos + i - 1.
            FIND FIRST ttContextEmbeddingTemp WHERE ttContextEmbeddingTemp.PosNo = iPos NO-ERROR.
//MESSAGE "iPos" iPos SKIP
//"AVAIL ttContextEmbeddingTemp" AVAIL ttContextEmbeddingTemp SKIP
//    VIEW-AS ALERT-BOX INFORMATION BUTTONS OK.
            IF AVAIL ttContextEmbeddingTemp THEN
            DO:
                ASSIGN iTargetTokenId = 0
                       dProbability   = ?.
                DO j = 1 TO {&VOCAB_SIZE}:
                    IF dProbability = ? THEN dProbability = ttContextEmbeddingTemp.Probabilities[j].
                    IF dProbability > ttContextEmbeddingTemp.Probabilities[j] THEN
                    DO:
                       ASSIGN iTargetTokenId = j
                              dProbability   = ttContextEmbeddingTemp.Probabilities[j].                           . 
                    END.                
                END.  
//MESSAGE "iTargetTokenId" iTargetTokenId SKIP
//    VIEW-AS ALERT-BOX INFORMATION BUTTONS OK.
                FIND ttEmbeddingsDictionary WHERE ttEmbeddingsDictionary.tokenId = iTargetTokenId AND iTargetTokenId > 0 NO-ERROR.
               
                 
                IF AVAIL ttEmbeddingsDictionary THEN DO:
                     //IF cPredictions <> "" THEN cPredictions = cPredictions + " ". 
                     cPredictions = cPredictions + ttEmbeddingsDictionary.cToken.
                END.
                    
            END.
        END.
//MESSAGE "cPredictions" cPredictions SKIP
//    VIEW-AS ALERT-BOX INFORMATION BUTTONS OK.
        RETURN cPredictions.
    END METHOD.

    METHOD PUBLIC LONGCHAR PrepareForBackwardPass(INPUT cTargetTokenIds AS CHARACTER):
        DEFINE VARIABLE i               AS INTEGER   NO-UNDO.
        DEFINE VARIABLE j               AS INTEGER   NO-UNDO.
        DEFINE VARIABLE iTargetCount    AS INTEGER   NO-UNDO.
        DEFINE VARIABLE iStartPos       AS INTEGER   NO-UNDO.
        DEFINE VARIABLE iPos            AS INTEGER   NO-UNDO.
        DEFINE VARIABLE iTargetTokenId  AS INTEGER   NO-UNDO.
        //DEFINE VARIABLE cToken          AS CHARACTER NO-UNDO.
        DEFINE VARIABLE lcOut           AS LONGCHAR  NO-UNDO.
        DEFINE VARIABLE cTokenIds       AS CHARACTER NO-UNDO EXTENT.
        
        /* Split the comma-separated list into an array */
        //cTokenIds = SUBSTITUTE("&1", cTargetTokenIds).
        iTargetCount = LENGTH(cTargetTokenIds).

        /* Defensive: Ensure we have at least that many positions in ttContextEmbeddingTemp */
        FIND LAST ttContextEmbeddingTemp NO-ERROR.
        IF NOT AVAILABLE ttContextEmbeddingTemp OR ttContextEmbeddingTemp.PosNo < iTargetCount THEN
            RETURN "ERROR: Not enough rows in ttContextEmbeddingTemp for training targets.".

        iStartPos = ttContextEmbeddingTemp.PosNo - iTargetCount + 1.

        DO i = 1 TO iTargetCount:
            iPos = iStartPos + i - 1.
            iTargetTokenId = INTEGER(ENTRY(i, cTargetTokenIds)) NO-ERROR.
            IF ERROR-STATUS:ERROR THEN
                NEXT.

            FIND ttContextEmbeddingTemp WHERE ttContextEmbeddingTemp.PosNo = iPos NO-ERROR.
            IF NOT AVAILABLE ttContextEmbeddingTemp THEN
                NEXT.

            /* Save target token id */
//          ASSIGN ttContextEmbeddingTemp.TargetTokenId = iTargetTokenId.

            /* Compute gradient for each logit */
            DO j = 1 TO {&VOCAB_SIZE}:
                ttContextEmbeddingTemp.GradLogit[j] =
                    ttContextEmbeddingTemp.Probabilities[j] -
                    (IF j = iTargetTokenId THEN 1 ELSE 0).
            END.
        END.
        TEMP-TABLE ttContextEmbeddingTemp:WRITE-JSON("longchar", lcOut, TRUE).
        RETURN lcOut.
        
    END METHOD.
        
END CLASS.
