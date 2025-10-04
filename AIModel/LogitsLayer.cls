USING Progress.Lang.*.
USING Progress.Json.ObjectModel.*.
USING AIModel.Layer.

CLASS AIModel.LogitsLayer INHERITS Layer:

    {AIModel/LayerSharedDefs.i}
    
    //DEFINE VARIABLE LearningRate AS DECIMAL     NO-UNDO INIT 0.01.
    
    DEFINE TEMP-TABLE ttContextEmbeddingTemp NO-UNDO SERIALIZE-NAME "ttContextEmbedding"  LIKE ttContextEmbedding.
    DEFINE TEMP-TABLE ttBackwardsOutput NO-UNDO SERIALIZE-NAME "ttContextEmbeddingTemp" LIKE ttContextEmbedding .
    //DEFINE TEMP-TABLE ttPersistedContextEmbedding NO-UNDO LIKE ttContextEmbedding.

    DEFINE TEMP-TABLE ttLogitsTemp NO-UNDO
        FIELD PosNo   AS INTEGER
        FIELD TokenId AS INTEGER
        FIELD Logits  AS DECIMAL EXTENT {&VOCAB_SIZE}.

 // DEFINE TEMP-TABLE ttLogitsWeights NO-UNDO
 //     FIELD EmbeddingIndex AS INTEGER
 //     FIELD VocabWeights   AS DECIMAL EXTENT {&VOCAB_SIZE}. /* Projection matrix */

    CONSTRUCTOR PUBLIC LogitsLayer(iLayerNo AS INT,iLayerCode AS CHAR, ihCallingProc AS HANDLE):  
        SUPER(iLayerNo,iLayerCode,ihCallingProc).
    END CONSTRUCTOR.
 
    METHOD PUBLIC OVERRIDE VOID initializeWeights():
        DEFINE VARIABLE i AS INTEGER NO-UNDO.
        DEFINE VARIABLE j AS INTEGER NO-UNDO.
        DEFINE VARIABLE dScale AS DECIMAL NO-UNDO.

        /* Optional: Scale based on size for more stable initial gradients */
        dScale = 1.0 / SQRT({&VOCAB_SIZE}).

        DO i = 1 TO {&EMBEDDING_SIZE}:
            CREATE ttLogitsWeights.
            ASSIGN ttLogitsWeights.EmbeddingIndex = i.

            DO j = 1 TO {&VOCAB_SIZE}:
                /* Initialize with small random values (e.g., [-0.5, 0.5] * dScale) */
                ttLogitsWeights.VocabWeights[j] = (RANDOM(-50, 50) / 100.0) * dScale.
            END.
        END.
    END METHOD.
        
    METHOD PUBLIC OVERRIDE LONGCHAR forward(INPUT lcInput AS LONGCHAR):
        DEFINE VARIABLE dDot     AS DECIMAL     NO-UNDO.
        DEFINE VARIABLE i        AS INTEGER     NO-UNDO.
        DEFINE VARIABLE j        AS INTEGER     NO-UNDO.
        DEFINE VARIABLE lcOutput AS LONGCHAR    NO-UNDO.
        EMPTY TEMP-TABLE ttContextEmbeddingTemp.
        TEMP-TABLE ttContextEmbeddingTemp:READ-JSON("longchar", lcInput, "empty").

        THIS-OBJECT:cloneContextEmbedding(INPUT BUFFER ttContextEmbeddingTemp:HANDLE,
                                          INPUT BUFFER ttPersistedContextEmbedding:HANDLE).

        FIX-CODEPAGE(lcOutput) = "UTF-8".

        EMPTY TEMP-TABLE ttLogits.
        FOR EACH ttContextEmbeddingTemp:
            CREATE ttLogits.
            ASSIGN ttLogits.PosNo = ttContextEmbeddingTemp.PosNo.

            DO i = 1 TO {&VOCAB_SIZE}:
                dDot = 0.
                DO j = 1 TO {&EMBEDDING_SIZE}:
                    FIND ttLogitsWeights WHERE ttLogitsWeights.EmbeddingIndex = j NO-ERROR.
                    IF NOT AVAIL ttLogitsWeights THEN NEXT.
                    dDot = dDot + ttContextEmbeddingTemp.weight[j] * ttLogitsWeights.VocabWeights[i].
                END.
                ttLogits.Logit[i] = dDot.
            END.
        END.

        /* Return original ttContextEmbeddingTemp (unchanged in forward here) */
        TEMP-TABLE ttContextEmbeddingTemp:WRITE-JSON("longchar", lcOutput, TRUE).

//TEMP-TABLE ttLogits:WRITE-JSON(SUBST("file","c:\temp\ttLogits_F_&1_&2.json",  
//                                      THIS-OBJECT:LayerCode,THIS-OBJECT:LayerNo), TRUE).
TEMP-TABLE ttLogits:WRITE-JSON("file","C:\temp\ttLogits.json",TRUE).
TEMP-TABLE ttContextEmbeddingTemp:WRITE-JSON("file",SUBST("c:\temp\ttContextEmbeddingTemp_F_&1_&2.json",
                                                           THIS-OBJECT:LayerCode,THIS-OBJECT:LayerNo), TRUE).        
        RETURN lcOutput.
    END METHOD.
            
    METHOD PUBLIC OVERRIDE LONGCHAR backward(INPUT lcGradLogits AS LONGCHAR):
        DEFINE VARIABLE i           AS INTEGER     NO-UNDO.
        DEFINE VARIABLE j           AS INTEGER     NO-UNDO.
        DEFINE VARIABLE delta       AS DECIMAL     NO-UNDO.
        DEFINE VARIABLE lr          AS DECIMAL     NO-UNDO INITIAL 0.01.
        DEFINE VARIABLE lcOutput    AS LONGCHAR    NO-UNDO.

        /* Read in the gradients w.r.t. logits */
        /* ttContextEmbeddingTemp reused here to hold GradLogit */
        EMPTY TEMP-TABLE ttContextEmbeddingTemp.
        EMPTY TEMP-TABLE ttBackwardsOutput.
        TEMP-TABLE ttContextEmbeddingTemp:READ-JSON("longchar", lcGradLogits, "empty").

        /* Zero out ttGradEmbedding */
        FOR EACH ttContextEmbeddingTemp:
            CREATE ttBackwardsOutput.
            BUFFER-COPY ttContextEmbeddingTemp EXCEPT weight GradLogit TO ttBackwardsOutput.
        END.

        FOR EACH ttContextEmbeddingTemp NO-LOCK:
            /* we need the original embedding that produced these logits */
            FIND FIRST ttPersistedContextEmbedding 
                WHERE ttPersistedContextEmbedding.PosNo = ttContextEmbeddingTemp.PosNo 
                  AND ttPersistedContextEmbedding.TokenId = ttContextEmbeddingTemp.TokenId NO-ERROR.
            IF NOT AVAILABLE ttPersistedContextEmbedding THEN NEXT.

            DO i = 1 TO {&VOCAB_SIZE}:
                /* delta for all weights projecting to logit i */
                /* delta_ji = GradLogit[i] * inputEmbedding[j] */
                /* update: W_ji -= lr * delta_ji */
                /* iterate over each embedding dimension j */
                DO j = 1 TO {&EMBEDDING_SIZE}:
                    /* read gradient for this logit */                            
                    delta = ttContextEmbeddingTemp.GradLogit[i]
                            * ttPersistedContextEmbedding.Weight[j].
                    /* update projection weight W[j][i] */
                    FIND FIRST ttLogitsWeights WHERE ttLogitsWeights.EmbeddingIndex = j NO-ERROR.
                    IF AVAILABLE ttLogitsWeights THEN
                        ASSIGN ttLogitsWeights.VocabWeights[i] = ttLogitsWeights.VocabWeights[i] - (THIS-OBJECT:LearningRate * delta).

                    /* accumulate gradient into embedding-grad[j] */
                    FIND FIRST ttBackwardsOutput 
                        WHERE ttBackwardsOutput.PosNo   = ttContextEmbeddingTemp.PosNo
                          AND ttBackwardsOutput.TokenId = ttContextEmbeddingTemp.TokenId NO-ERROR.
                    IF NOT AVAIL ttBackwardsOutput THEN NEXT.
                    ASSIGN
                      ttBackwardsOutput.Weight[j] = ttBackwardsOutput.Weight[j] + delta.
                END.
            END.
        END.

        /* Serialize the embedding-gradients for the next layer */
        TEMP-TABLE ttBackwardsOutput:WRITE-JSON("longchar", lcOutput, TRUE).
        RETURN lcOutput.
    END METHOD.
    
    METHOD PUBLIC VOID passTtLogits (OUTPUT TABLE ttLogits):
    
    END METHOD.
    
    METHOD PUBLIC OVERRIDE JsonObject serialize():
        DEFINE VARIABLE oJson AS JsonObject NO-UNDO.
        oJson = NEW JsonObject().
        TEMP-TABLE ttLogitsWeights:WRITE-JSON("JSONOBJECT", oJson, TRUE).
        RETURN oJson.
    END METHOD.
    
    METHOD PUBLIC OVERRIDE VOID deserialize(INPUT oJson AS JsonObject):
        TEMP-TABLE ttLogitsWeights:READ-JSON("JSONOBJECT", oJson, "empty").
    END METHOD.
   


END CLASS.
