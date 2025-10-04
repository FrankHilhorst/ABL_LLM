USING Progress.Json.ObjectModel.JsonObject.
USING AIModel.Layer.

USING Progress.Json.ObjectModel.JsonObject.
USING Progress.Json.ObjectModel.ObjectModelParser.
USING AIModel.Layer.

CLASS FeedForwardLayer INHERITS Layer:

    {AIModel/LayerSharedDefs.i}
    
    DEFINE VARIABLE LearningRate AS DECIMAL     NO-UNDO INIT 0.01.

    DEFINE TEMP-TABLE ttContextEmbeddingTemp NO-UNDO LIKE ttContextEmbedding.
    //DEFINE TEMP-TABLE ttPersistedContextEmbedding  NO-UNDO LIKE ttContextEmbeddingTemp.

    DEFINE TEMP-TABLE ttContextEmbeddingFF NO-UNDO LIKE ttContextEmbeddingTemp
       FIELD FFW1_Weight  AS DECIMAL EXTENT {&FF_DIM}      
       FIELD FFW2_Weight  AS DECIMAL EXTENT {&EMBEDDING_SIZE}
       FIELD FFB1_Bias    AS DECIMAL EXTENT {&FF_DIM}
       FIELD FFB2_Bias    AS DECIMAL EXTENT {&EMBEDDING_SIZE}.
    
    DEFINE TEMP-TABLE ttFFState NO-UNDO
        FIELD PosNo   AS INTEGER
        FIELD TokenId AS INTEGER
        FIELD Z1      AS DECIMAL EXTENT {&FF_DIM}
        FIELD H       AS DECIMAL EXTENT {&FF_DIM}
        FIELD X       AS DECIMAL EXTENT {&EMBEDDING_SIZE}.
        
   DEFINE TEMP-TABLE ttFeedForward NO-UNDO
       FIELD FFW1_Weight  AS DECIMAL EXTENT {&FF_DIM}      
       FIELD FFW2_Weight  AS DECIMAL EXTENT {&EMBEDDING_SIZE}
       FIELD FFB1_Bias    AS DECIMAL EXTENT {&FF_DIM}
       FIELD FFB2_Bias    AS DECIMAL EXTENT {&EMBEDDING_SIZE}.
    
    METHOD PUBLIC OVERRIDE VOID initializeWeights():
       DEFINE VARIABLE i AS INTEGER     NO-UNDO.
       FIND FIRST ttFeedForward NO-ERROR.
       IF NOT AVAIL ttFeedForward THEN CREATE ttFeedForward.
       DO i = 1 TO EXTENT(ttFeedForward.FFW1_Weight):
          ttFeedForward.FFW1_Weight[i] = RANDOM(-50, 50) / 100.0.
       END.
       DO i = 1 TO EXTENT(ttFeedForward.FFW2_Weight):
          ttFeedForward.FFW2_Weight[i] = RANDOM(-50, 50) / 100.0.
       END.
       ttFeedForward.FFB1_Bias = 0.
       ttFeedForward.FFB2_Bias = 0.
    
    END METHOD.
/*************************************    
    METHOD PUBLIC OVERRIDE VOID initializeWeights():
        DEFINE VARIABLE i AS INTEGER NO-UNDO.
        DEFINE VARIABLE j AS INTEGER NO-UNDO.

        /* Randomly initialize weights */
        DO i = 1 TO {&EMBEDDING_SIZE}:
            CREATE ttFFW1.
            ttFFW1.PosNo = i.
            DO j = 1 TO {&FF_DIM}:
                ttFFW1.Weight[j] = RANDOM(-50, 50) / 100.0.
            END.
        END.
        CREATE ttFFB1.
        ttFFB1.Bias = 0.
//      DO i = 1 TO {&FF_DIM}:
//          CREATE ttFFB1.
//          ttFFB1.Bias[i] = 0.
//      END.

        DO i = 1 TO {&FF_DIM}:
            CREATE ttFFW2.
            ttFFW2.PosNo = i.
            DO j = 1 TO {&EMBEDDING_SIZE}:
                ttFFW2.Weight[j] = RANDOM(-50, 50) / 100.0.
            END.
        END.

        CREATE ttFFB2.
        ttFFB2.Bias = 0.
        
//      DO i = 1 TO {&EMBEDDING_SIZE}:
//          CREATE ttFFB2.
//          ttFFB2.Bias[i] = 0.
//      END.
    END METHOD.

 *****/   
    METHOD PUBLIC OVERRIDE JsonObject serialize():
       DEF VAR oJsonTbl  AS JsonObject NO-UNDO.
       oJsonTbl = NEW JsonObject().       
       TEMP-TABLE ttFeedForward:WRITE-JSON("JsonObject",oJsonTbl,TRUE). 
       RETURN oJsonTbl.
    END METHOD. 
    
    METHOD PUBLIC OVERRIDE VOID deserialize(INPUT oJson AS JsonObject):
        TEMP-TABLE ttFeedForward:READ-JSON("JsonObject",oJson,"empty").    
    END METHOD.
    
    METHOD PRIVATE VOID captureState(INPUT hSourceTable AS HANDLE, 
                                     INPUT icSrcFldNm   AS CHAR,
                                     INPUT icDestFieldNm AS CHAR):
                                     
        DEFINE VARIABLE hBuffer     AS HANDLE     NO-UNDO.
//        DEFINE VARIABLE hField      AS HANDLE     NO-UNDO.
        DEFINE VARIABLE hQuery      AS HANDLE     NO-UNDO.
        DEFINE VARIABLE cFieldList  AS CHARACTER  NO-UNDO.
        DEFINE VARIABLE arrValue    AS DECIMAL    EXTENT.
        DEFINE VARIABLE i           AS INTEGER    NO-UNDO.
        DEFINE VARIABLE iPos        AS INTEGER    NO-UNDO.
        DEFINE VARIABLE iTokenId    AS INTEGER    NO-UNDO.
        DEFINE VARIABLE hSrcFld     AS HANDLE     NO-UNDO.
        DEFINE VARIABLE hDestFld    AS HANDLE     NO-UNDO.

        CREATE BUFFER hBuffer FOR TABLE hSourceTable.
        ASSIGN hSrcFld = hBuffer:BUFFER-FIELD(icSrcFldNm).
               hDestFld = BUFFER ttFFState:BUFFER-FIELD(icDestFieldNm).
        /* Create dynamic query on the source table */
        CREATE QUERY hQuery.
        hQuery:ADD-BUFFER(hBuffer).
        hQuery:QUERY-PREPARE(SUBST("FOR EACH &1",hSourceTable:NAME)).
        hQuery:QUERY-OPEN().

        hQuery:GET-FIRST().
        REPEAT WHILE hQuery:QUERY-OFF-END:
            /* Extract PosNo and TokenId fields */

            ASSIGN iPos = 0 iTokenId = 0.
            iPos = hBuffer:BUFFER-FIELD("PosNo"):BUFFER-VALUE NO-ERROR.
            iTokenId = hBuffer:BUFFER-FIELD("TokenId"):BUFFER-VALUE.
            FIND FIRST ttFFState WHERE ttFFState.posNo = iPos AND ttFFState.TokenId = iTokenId NO-ERROR.
            IF NOT AVAIL ttFFState THEN
            DO:
                CREATE ttFFState.
                ASSIGN ttFFState.PosNo = iPos 
                       ttFFState.tokenId = iTokenId.                
            END.
            DO i = 1 TO hSrcFld:EXTENT:
               hDestFld:BUFFER-VALUE(i) = hSrcFld:BUFFER-VALUE(i).
            END.
            hQuery:GET-NEXT().
        END.
        FINALLY:           
           DELETE OBJECT hQuery.
           DELETE OBJECT hBuffer NO-ERROR.
        END FINALLY.
    END METHOD.
 
    METHOD PUBLIC OVERRIDE LONGCHAR forward(INPUT lcInput AS LONGCHAR):
        DEFINE VARIABLE lcOutput AS LONGCHAR NO-UNDO.
        DEFINE VARIABLE i        AS INTEGER  NO-UNDO.
        DEFINE VARIABLE j        AS INTEGER  NO-UNDO.
        DEFINE VARIABLE k        AS INTEGER  NO-UNDO.
        DEFINE VARIABLE z1       AS DECIMAL  EXTENT {&FF_DIM} NO-UNDO.
        DEFINE VARIABLE h        AS DECIMAL  EXTENT {&FF_DIM} NO-UNDO.
        DEFINE VARIABLE z2       AS DECIMAL  EXTENT {&EMBEDDING_SIZE} NO-UNDO.

        DEFINE BUFFER bInput     FOR ttContextEmbeddingTemp.
        DEFINE BUFFER bOutput    FOR ttContextEmbeddingTemp.
        DEFINE BUFFER bFF        FOR ttFeedForward.

        TEMP-TABLE ttContextEmbeddingTemp:READ-JSON("longchar", lcInput, "empty").

        /* Find the one row of weights and biases */
        FIND bFF NO-LOCK NO-ERROR.
        IF NOT AVAILABLE bFF THEN
            UNDO, THROW NEW PROGRESS.lang.AppError("Error: FeedForward parameters not initialized.",9).

        /* Clear any existing output */
        FOR EACH bOutput:
            DELETE bOutput.
        END.

        FOR EACH bInput NO-LOCK:
            /* Step 1: Compute z1 = W1 * x + b1 */
/*******            
            DO j = 1 TO {&FF_DIM}:
                z1 = 0.
                DO k = 1 TO {&EMBEDDING_SIZE}:
                    z1[j] = z1[j] + bFF.FFW1_Weight[j] * bInput.Weight[k].
                END.
                bInput.HiddenPreActivation[j] = z1[j].
                bInput.reluWeight[j] = MAXIMUM(z1[j], 0). 
                z1[j] = z1[j] + bFF.FFB1_Bias[j].                
            END.
*********/            
            DO j = 1 TO {&FF_DIM}:
                z1[j] = 0.
                DO k = 1 TO {&EMBEDDING_SIZE}:
                    z1[j] = z1[j] + bInput.Weight[k] * bFF.FFW1_Weight[j].
                    /* or ideally: bFF.FFW1_Weight[j][k] if you're storing 2D weights */
                END.
                
                /* Add the bias AFTER the dot product */
                z1[j] = z1[j] + bFF.FFB1_Bias[j].

                /* Save pre-activation value (z1) */
                bInput.HiddenPreActivation[j] = z1[j].

                /* Apply ReLU and store */
                bInput.reluWeight[j] = MAXIMUM(z1[j], 0).
            END.
            /* Step 2: Apply activation h = ReLU(z1) */
            DO j = 1 TO {&FF_DIM}:
                h[j] = MAXIMUM(0, z1[j]).
            END.

            /* Step 3: Compute z2 = W2 * h + b2 */
            DO i = 1 TO {&EMBEDDING_SIZE}:
                z2[i] = bFF.FFB2_Bias[i].
                DO j = 1 TO {&FF_DIM}:
                    z2[i] = z2[i] + bFF.FFW2_Weight[i] * h[j].
                END.
            END.

            /* Output result */
            CREATE bOutput.
            ASSIGN
                bOutput.PosNo   = bInput.PosNo
                bOutput.TokenId = bInput.TokenId.

            DO i = 1 TO {&EMBEDDING_SIZE}:
                bOutput.Weight[i] = z2[i].
            END.
        END.

        //ttPersistedContextEmbedding  NO-UNDO LIKE ttContextEmbeddingTemp.
        THIS-OBJECT:cloneContextEmbedding(INPUT BUFFER ttContextEmbeddingTemp:HANDLE,
                                          INPUT BUFFER ttPersistedContextEmbedding:HANDLE).
 
        TEMP-TABLE ttContextEmbeddingTemp:WRITE-JSON("longchar", lcOutput, TRUE).
        RETURN lcOutput.
    END METHOD.

    METHOD PUBLIC OVERRIDE LONGCHAR backward(INPUT lcGradOutput AS LONGCHAR):
        DEFINE VARIABLE i       AS INTEGER     NO-UNDO.
        DEFINE VARIABLE dWeight AS DECIMAL     NO-UNDO.
        DEFINE VARIABLE dBias   AS DECIMAL     NO-UNDO.
        DEFINE VARIABLE lcJson  AS LONGCHAR    NO-UNDO.
        TEMP-TABLE ttContextEmbeddingTemp:READ-JSON("longchar", lcGradOutput, "EMPTY").

        FIND FIRST ttFeedForward.
        
        FOR EACH ttContextEmbeddingTemp:
            CREATE ttContextEmbeddingFF.
            BUFFER-COPY ttContextEmbeddingTemp TO ttContextEmbeddingFF.
        END.
        FOR EACH ttContextEmbeddingFF:
            FIND ttPersistedContextEmbedding WHERE ttPersistedContextEmbedding.PosNo = ttContextEmbeddingFF.posNo AND
                                                   ttPersistedContextEmbedding.TokenId = ttContextEmbeddingFF.TokenId NO-ERROR.
            IF NOT AVAIL ttPersistedContextEmbedding THEN NEXT.
            DO i = 1 TO EXTENT(ttContextEmbeddingFF.FFW1_Weight):
               THIS-OBJECT:gradient(
                    INPUT  LearningRate,
                    INPUT  ttPersistedContextEmbedding.HiddenPreActivation[i],   /* dInput: x[i] */
                    INPUT  ttPersistedContextEmbedding.Weight[i],   /* dOldValue */
                    INPUT  ttContextEmbeddingFF.Weight[i],          /* dNewValue (corrected output) */
                    INPUT  ttFeedForward.FFW1_Weight[i],
                    INPUT  ttFeedForward.FFB1_Bias[i],
                    OUTPUT dWeight,
                    OUTPUT dBias).                                     
                ASSIGN ttContextEmbeddingFF.FFW1_Weight[i] = dWeight   
                       ttContextEmbeddingFF.FFB1_Bias[i] = dBias.
            END.
            DO i = 1 TO EXTENT(ttContextEmbeddingFF.FFW2_Weight):
                THIS-OBJECT:gradient(INPUT LearningRate,
                                     INPUT ttContextEmbeddingFF.ReluWeight[i],  //input
                                     INPUT ttContextEmbeddingFF.weight[i],
                                     INPUT ttPersistedContextEmbedding.weight[i],   
                                     INPUT ttFeedForward.FFW2_Weight[i],
                                     INPUT ttFeedForward.FFB2_Bias[i],
                                     OUTPUT dWeight,       
                                     OUTPUT dBias).        
                ASSIGN ttContextEmbeddingFF.FFW2_Weight[i] = dWeight   
                       ttContextEmbeddingFF.FFB2_Bias[i] = dBias.
                                     
            END. 
        END.
        DO i = 1 TO EXTENT(ttFeedForward.FFW1_Weight):
            ASSIGN ttFeedForward.FFW1_Weight[i] = THIS-OBJECT:CalcAvg(BUFFER ttContextEmbeddingFF:HANDLE, BUFFER ttContextEmbeddingFF:BUFFER-FIELD("FFW1_Weight"),i)
                   ttFeedForward.FFB1_Bias[i]   = THIS-OBJECT:CalcAvg(BUFFER ttContextEmbeddingFF:HANDLE, BUFFER ttContextEmbeddingFF:BUFFER-FIELD("FFB1_Bias"),i).            .
        END.
        DO i = 1 TO EXTENT(ttFeedForward.FFW2_Weight):
            ASSIGN ttFeedForward.FFW2_Weight[i] = THIS-OBJECT:CalcAvg(BUFFER ttContextEmbeddingFF:HANDLE, BUFFER ttContextEmbeddingFF:BUFFER-FIELD("FFW2_Weight"),i)
                   ttFeedForward.FFB2_Bias[i]   = THIS-OBJECT:CalcAvg(BUFFER ttContextEmbeddingFF:HANDLE, BUFFER ttContextEmbeddingFF:BUFFER-FIELD("FFB2_Bias"),i).            .
        END.
        TEMP-TABLE ttPersistedContextEmbedding:WRITE-JSON("longchar",lcJson,TRUE).
        RETURN THIS-OBJECT:FORWARD(lcJson).
        
    END METHOD.
    
    METHOD PRIVATE DECIMAL calcAvg( hBuffer AS HANDLE,hBufFld AS HANDLE, iIdx AS INT):
        DEFINE VARIABLE hQuery AS HANDLE      NO-UNDO.
        DEFINE VARIABLE dTot   AS DECIMAL     NO-UNDO.
        DEFINE VARIABLE i      AS INTEGER     NO-UNDO.
        CREATE QUERY hQuery.
        hQuery:ADD-BUFFER(hBuffer).
        hQuery:QUERY-PREPARE(SUBST("for each &1",hBuffer:NAME)).
        hQuery:GET-FIRST().
        DO WHILE NOT hQuery:QUERY-OFF-END:
            ASSIGN dTot = dTot + hBufFld:BUFFER-VALUE(iIdx)
                   i = i + 1.
            hQuery:GET-NEXT().
        END.
        hQuery:QUERY-CLOSE().
        DELETE OBJECT hQuery NO-ERROR.
        RETURN dTot / i.
    END METHOD.
    
 /***************************************   
    METHOD PUBLIC OVERRIDE LONGCHAR backward(INPUT lcGradOutput AS LONGCHAR):
        DEFINE VARIABLE i            AS INTEGER  NO-UNDO.
        DEFINE VARIABLE j            AS INTEGER  NO-UNDO.
        DEFINE VARIABLE k            AS INTEGER  NO-UNDO.
        DEFINE VARIABLE learningRate AS DECIMAL  NO-UNDO INITIAL 0.01.
        DEFINE VARIABLE yGrad        AS DECIMAL  EXTENT {&EMBEDDING_SIZE}.
        DEFINE VARIABLE h            AS DECIMAL  EXTENT {&FF_DIM}.
        DEFINE VARIABLE hGrad        AS DECIMAL  EXTENT {&FF_DIM}.
        DEFINE VARIABLE x            AS DECIMAL  EXTENT {&EMBEDDING_SIZE}.
        DEFINE VARIABLE xGrad        AS DECIMAL  EXTENT {&EMBEDDING_SIZE}.
        DEFINE VARIABLE lcOut        AS LONGCHAR NO-UNDO.

        DEFINE BUFFER ttGradOut  FOR ttContextEmbeddingTemp.
        DEFINE BUFFER ttPersist  FOR ttPersistedContextEmbedding.
        DEFINE BUFFER ttFF       FOR ttFeedForward.

        TEMP-TABLE ttContextEmbeddingTemp:READ-JSON("longchar", lcGradOutput, "EMPTY").

        FIND FIRST ttFF EXCLUSIVE-LOCK NO-ERROR.
        IF NOT AVAILABLE ttFF THEN RETURN "". /* safety check */

        /* Loop over each token position */
        FOR EACH ttGradOut:
            FIND ttPersist WHERE
                ttPersist.PosNo = ttGradOut.PosNo AND
                ttPersist.TokenId = ttGradOut.TokenId NO-LOCK NO-ERROR.

            IF NOT AVAILABLE ttPersist THEN NEXT.

            /* yGrad: gradient of loss w.r.t. output */
            DO i = 1 TO {&EMBEDDING_SIZE}:
                yGrad[i] = ttGradOut.Weight[i].
            END.

            /* Reconstruct x */
            DO i = 1 TO {&EMBEDDING_SIZE}:
                x[i] = ttPersist.Weight[i].
            END.

            /* Forward pass (recompute h = ReLU(x * W1 + b1)) */
            DO j = 1 TO {&FF_DIM}:
                h[j] = ttFF.FFB1_Bias[j].
                DO i = 1 TO {&EMBEDDING_SIZE}:
                    h[j] = h[j] + x[i] * ttFF.FFW1_Weight[j].
                END.
                IF h[j] < 0 THEN h[j] = 0.
            END.

            /* Compute gradient for W2 and b2 */
            DO i = 1 TO {&EMBEDDING_SIZE}:
                DO j = 1 TO {&FF_DIM}:
                    ttFF.FFW2_Weight[i] = ttFF.FFW2_Weight[i] - learningRate * yGrad[i] * h[j].
                END.
                ttFF.FFB2_Bias[i] = ttFF.FFB2_Bias[i] - learningRate * yGrad[i].
            END.

            /* Backprop through W2 to get hGrad */
            DO j = 1 TO {&FF_DIM}:
                hGrad[j] = 0.
                DO i = 1 TO {&EMBEDDING_SIZE}:
                    hGrad[j] = hGrad[j] + yGrad[i] * ttFF.FFW2_Weight[i].
                END.
                IF h[j] <= 0 THEN hGrad[j] = 0. /* ReLU backward */
            END.

            /* Update W1 and b1, and compute xGrad */
            DO i = 1 TO {&EMBEDDING_SIZE}:
                xGrad[i] = 0.
                DO j = 1 TO {&FF_DIM}:
                    ttFF.FFW1_Weight[j] = ttFF.FFW1_Weight[j] - learningRate * hGrad[j] * x[i].
                    xGrad[i] = xGrad[i] + hGrad[j] * ttFF.FFW1_Weight[j].
                END.
            END.

            /* Replace ttGradOut.Weight with xGrad for next layer */
            DO i = 1 TO {&EMBEDDING_SIZE}:
                ttGradOut.Weight[i] = xGrad[i].
            END.
        END. /*..FOR EACH ttGradOut:..*/

        TEMP-TABLE ttContextEmbeddingTemp:WRITE-JSON("LONGCHAR", lcOut, TRUE).
        RETURN lcOut.
    END METHOD.
 ***********************/   
    METHOD PRIVATE VOID gradient(
        INPUT  dLearningRate AS DECIMAL,
        INPUT  dInput        AS DECIMAL,    /* input to the neuron */
        INPUT  dOldValue     AS DECIMAL,    /* output before correction */
        INPUT  dNewValue     AS DECIMAL,    /* target/corrected output */
        INPUT  dOldWeight    AS DECIMAL,
        INPUT  dOldBias      AS DECIMAL,
        OUTPUT dNewWeight    AS DECIMAL,
        OUTPUT dNewBias      AS DECIMAL
    ):
        DEFINE VARIABLE dDelta        AS DECIMAL NO-UNDO.
        DEFINE VARIABLE dDeltaWeight  AS DECIMAL NO-UNDO.
        DEFINE VARIABLE dDeltaBias    AS DECIMAL NO-UNDO.
        DEFINE VARIABLE reluDerivative AS DECIMAL NO-UNDO.

        /* ReLU derivative: if the neuron was inactive (<=0), gradient is zero */
        reluDerivative = IF dOldValue > 0 THEN 1 ELSE 0.

        /* Calculate the delta (error signal), and scale by ReLU derivative */
        dDelta = (dOldValue - dNewValue) * reluDerivative.

        /* Standard gradient descent update rule */
        dDeltaWeight = dDelta * dInput * dLearningRate.
        dDeltaBias   = dDelta * dLearningRate.

        /* Update weights and biases */
        dNewWeight = dOldWeight - dDeltaWeight.
        dNewBias   = dOldBias - dDeltaBias.
    END METHOD.
/*********************************    
    METHOD PRIVATE VOID greadient( INPUT dLearningRate AS DEC,
                                   INPUT dOldValue AS DEC,
                                   INPUT dNewValue AS DEC,
                                   INPUT dOldWeight AS DEC,
                                   INPUT dOLdBias AS DEC,
                                   OUTPUT dNewWeight AS DEC,
                                   OUTPUT dNewBias AS DEC):
                                   
        DEFINE VARIABLE dDeltaValue  AS DECIMAL     NO-UNDO.
        DEFINE VARIABLE dDeltaWeight AS DECIMAL     NO-UNDO.
        DEFINE VARIABLE dDeltaBias   AS DECIMAL     NO-UNDO.
        ASSIGN dDeltaValue  = dOldValue - dNewValue
               dDeltaWeight = dDeltaValue * MAX(dOldWeight * dLearningRate,0)
               dNewWeight = dOldValue - dDeltaWeight
               dDeltaBias = dDeltaValue * dLearningRate. 
        
    END METHOD.                               
*********************************/   
   
                                   
     
END CLASS.
