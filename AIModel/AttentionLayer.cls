USING Progress.Json.ObjectModel.JsonObject.
USING AIModel.Layer.

CLASS AIModel.AttentionLayer INHERITS Layer:

    /* Include shared layer definitions: constants and context table */
    {AIModel/LayerSharedDefs.i}

    /* Self-attention transformation weights: separate Q, K, V for each context position */
    DEFINE TEMP-TABLE ttAttentionMatrix NO-UNDO
        FIELD PosNo AS INTEGER
        FIELD Q     AS DECIMAL EXTENT {&EMBEDDING_SIZE}
        FIELD K     AS DECIMAL EXTENT {&EMBEDDING_SIZE}
        FIELD V     AS DECIMAL EXTENT {&EMBEDDING_SIZE}.
        
    DEFINE TEMP-TABLE ttAttentionState NO-UNDO
        FIELD PosNo        AS INTEGER
        FIELD TokenId      AS INTEGER
        FIELD Qry          AS DECIMAL EXTENT {&EMBEDDING_SIZE}
        FIELD SoftmaxTotal AS DECIMAL
        FIELD AttnWeight   AS DECIMAL EXTENT {&MAX_SEQUENCE_LENGTH}.

    DEFINE TEMP-TABLE ttAttentionStatePars NO-UNDO
        FIELD PosNo   AS INTEGER
        FIELD IdxNo   AS INTEGER
        FIELD K       AS DECIMAL EXTENT {&EMBEDDING_SIZE}
        FIELD V       AS DECIMAL EXTENT {&EMBEDDING_SIZE}.
       
    /* Class-scope temp-tables (place these in the PRIVATE section of the class) */

   /* We'll store computed Q, K, V vectors in temp-tables */
    DEFINE TEMP-TABLE ttContextEmbeddingTemp NO-UNDO SERIALIZE-NAME "ttContextEmbedding" LIKE ttContextEmbedding.
    DEFINE TEMP-TABLE ttOutput NO-UNDO LIKE ttContextEmbedding.

    DEFINE TEMP-TABLE ttAttentionScore NO-UNDO
        FIELD PosNo  AS INTEGER
        FIELD Score  AS DECIMAL.
        
    CONSTRUCTOR PUBLIC AttentionLayer(iLayerNo AS INT,iLayerCode AS CHAR, ihCallingProc AS HANDLE):  
        SUPER(iLayerNo,iLayerCode,ihCallingProc). 
    END CONSTRUCTOR.

    METHOD PRIVATE VOID cloneContextEmbedding():
        DEFINE BUFFER bSource FOR ttContextEmbedding.
        DEFINE BUFFER bClone  FOR ttPersistedContextEmbedding.

        EMPTY TEMP-TABLE ttPersistedContextEmbedding.
        FOR EACH bSource:
            CREATE bClone.
            BUFFER-COPY bSource TO bClone.
        END.
    END METHOD.
    
    METHOD PUBLIC OVERRIDE VOID initializeWeights():
        DEFINE VARIABLE i AS INTEGER NO-UNDO.
        DEFINE VARIABLE j AS INTEGER NO-UNDO.

        DO i = 1 TO {&VOCAB_SIZE}:
            CREATE ttAttentionMatrix.
            ASSIGN ttAttentionMatrix.PosNo = i.
            DO j = 1 TO {&EMBEDDING_SIZE}:
                ttAttentionMatrix.Q[j] = (RANDOM(0,1000) / 1000.0) * 0.02 - 0.01.
                ttAttentionMatrix.K[j] = (RANDOM(0,1000) / 1000.0) * 0.02 - 0.01.
                ttAttentionMatrix.V[j] = (RANDOM(0,1000) / 1000.0) * 0.02 - 0.01.
            END.
        END.
    END METHOD.

    METHOD PUBLIC OVERRIDE JsonObject serialize():
        DEFINE VARIABLE oJson AS JsonObject NO-UNDO.
        oJson = NEW JsonObject().
        TEMP-TABLE ttAttentionMatrix:WRITE-JSON("JSONOBJECT", oJson, TRUE).
        RETURN oJson.
    END METHOD.

    METHOD PUBLIC OVERRIDE VOID deserialize(INPUT oJson AS JsonObject):
        TEMP-TABLE ttAttentionMatrix:READ-JSON("JSONOBJECT", oJson, "empty").
    END METHOD.

    METHOD PUBLIC OVERRIDE LONGCHAR forward(INPUT lcInput AS LONGCHAR):
        DEFINE VARIABLE lcOutput     AS LONGCHAR NO-UNDO.
        DEFINE VARIABLE scaleFactor  AS DECIMAL  NO-UNDO.
        DEFINE VARIABLE score        AS DECIMAL  NO-UNDO.
        DEFINE VARIABLE sumScores    AS DECIMAL  NO-UNDO.
        DEFINE VARIABLE i            AS INTEGER  NO-UNDO.
        DEFINE VARIABLE j            AS INTEGER  NO-UNDO.
        DEFINE VARIABLE k            AS INTEGER  NO-UNDO.
        DEFINE VARIABLE attnWeight   AS DECIMAL  EXTENT {&MAX_SEQUENCE_LENGTH}.
        DEFINE VARIABLE attnSum      AS DECIMAL  EXTENT {&EMBEDDING_SIZE}.

        DEFINE BUFFER ttQ         FOR ttContextEmbedding.
        DEFINE BUFFER ttK         FOR ttContextEmbedding.
        DEFINE BUFFER ttV         FOR ttContextEmbedding.
        DEFINE BUFFER ttKMat      FOR ttAttentionMatrix.
        DEFINE BUFFER ttVMat      FOR ttAttentionMatrix.
        DEFINE BUFFER ttStatePars FOR ttAttentionStatePars.

        EMPTY TEMP-TABLE ttContextEmbeddingTemp.
        TEMP-TABLE ttContextEmbedding:READ-JSON("LONGCHAR", lcInput, "empty").

        THIS-OBJECT:cloneContextEmbedding().
        
        scaleFactor = 1.0 / SQRT({&EMBEDDING_SIZE}).

        /* Iterate over each token (Q row) */
        FOR EACH ttQ NO-LOCK:

            /* Find the Q vector */
            FIND FIRST ttAttentionMatrix WHERE ttAttentionMatrix.PosNo = ttQ.PosNo NO-LOCK NO-ERROR.
            IF NOT AVAILABLE ttAttentionMatrix THEN NEXT.

            /* Save Q for this token */
            CREATE ttAttentionState.
            ASSIGN
                ttAttentionState.PosNo = ttQ.PosNo
                ttAttentionState.TokenId = ttQ.TokenId
                ttAttentionState.AttnWeight = 0. /* Initialized */

            DO i = 1 TO {&EMBEDDING_SIZE}:
                ttAttentionState.Q[i] = ttAttentionMatrix.Q[i].
            END.

            /* Compute attention weights and save K, V in ttAttentionStatePars */
            j = 0.
            sumScores = 0.
            FOR EACH ttK NO-LOCK:
                j = j + 1.

                FIND ttKMat WHERE ttKMat.PosNo = ttK.PosNo NO-LOCK NO-ERROR.
                FIND ttVMat WHERE ttVMat.PosNo = ttK.PosNo NO-LOCK NO-ERROR.

                IF NOT (AVAILABLE ttKMat AND AVAILABLE ttVMat) THEN NEXT.

                /* Save K and V vectors */
                CREATE ttStatePars.
                ASSIGN
                    ttStatePars.PosNo = ttQ.PosNo
                    ttStatePars.IdxNo = j.

                DO k = 1 TO {&EMBEDDING_SIZE}:
                    ttStatePars.K[k] = ttKMat.K[k].
                    ttStatePars.V[k] = ttVMat.V[k].
                END.

                /* Compute dot product Q . K */
                score = 0.
                DO k = 1 TO {&EMBEDDING_SIZE}:
                    score = score + ttAttentionMatrix.Q[k] * ttKMat.K[k].
                END.
                score = score * scaleFactor.

                attnWeight[j] = EXP(2.71828, score).
                sumScores = sumScores + attnWeight[j].
            END.

            /* Normalize attention weights and store in ttAttentionState */
            DO i = 1 TO j:
                attnWeight[i] = attnWeight[i] / sumScores.
                ttAttentionState.AttnWeight[i] = attnWeight[i].
            END.

            /* Compute weighted sum over V */
            attnSum = 0.
            FOR EACH ttStatePars WHERE ttStatePars.PosNo = ttQ.PosNo NO-LOCK BY ttStatePars.IdxNo:
                j = ttStatePars.IdxNo.
                DO k = 1 TO {&EMBEDDING_SIZE}:
                    attnSum[k] = attnSum[k] + ttAttentionState.AttnWeight[j] * ttStatePars.V[k].
                END.
            END.

            /* Add attention result to output */
            CREATE ttContextEmbeddingTemp.
            ASSIGN
                ttContextEmbeddingTemp.PosNo   = ttQ.PosNo
                ttContextEmbeddingTemp.TokenId = ttQ.TokenId.
            DO i = 1 TO {&EMBEDDING_SIZE}:
                ttContextEmbeddingTemp.Weight[i] = attnSum[i].
            END.
        END.

        TEMP-TABLE ttContextEmbeddingTemp:WRITE-JSON("LONGCHAR", lcOutput, TRUE).

TEMP-TABLE ttContextEmbeddingTemp:WRITE-JSON("file",SUBST("c:\temp\ttContextEmbeddingTemp_F_&1_&2.json",
                                                           THIS-OBJECT:LayerCode,THIS-OBJECT:LayerNo), TRUE).        
        RETURN lcOutput.
    END METHOD.

    METHOD PUBLIC OVERRIDE LONGCHAR backward(INPUT lcGradOutput AS LONGCHAR):
        DEFINE VARIABLE scaleFactor  AS DECIMAL  NO-UNDO.
        DEFINE VARIABLE i            AS INTEGER  NO-UNDO.
        DEFINE VARIABLE j            AS INTEGER  NO-UNDO.
        DEFINE VARIABLE k            AS INTEGER  NO-UNDO.
//      DEFINE VARIABLE learningRate AS DECIMAL  NO-UNDO INITIAL 0.01.
        DEFINE VARIABLE dOut         AS DECIMAL  EXTENT {&EMBEDDING_SIZE}.
        DEFINE VARIABLE dQ           AS DECIMAL  EXTENT {&EMBEDDING_SIZE}.
        DEFINE VARIABLE dK           AS DECIMAL  EXTENT {&EMBEDDING_SIZE}.
        DEFINE VARIABLE dV           AS DECIMAL  EXTENT {&EMBEDDING_SIZE}.
        DEFINE VARIABLE dotProd      AS DECIMAL  NO-UNDO.
        DEFINE VARIABLE delta        AS DECIMAL  NO-UNDO.
        DEFINE VARIABLE lcOutput     AS LONGCHAR NO-UNDO.

        DEFINE BUFFER ttGradOut     FOR ttContextEmbeddingTemp.
        DEFINE BUFFER ttState       FOR ttAttentionState.
        DEFINE BUFFER ttStatePars   FOR ttAttentionStatePars.
        DEFINE BUFFER ttMatQ        FOR ttAttentionMatrix.
        DEFINE BUFFER ttMatKV       FOR ttAttentionMatrix.

        EMPTY TEMP-TABLE ttContextEmbeddingTemp.
        TEMP-TABLE ttContextEmbeddingTemp:READ-JSON("LONGCHAR", lcGradOutput, "empty").

        scaleFactor = 1.0 / SQRT({&EMBEDDING_SIZE}).

        FOR EACH ttGradOut NO-LOCK:

            /* Get saved Q and attention weights */
            FIND ttState WHERE ttState.PosNo = ttGradOut.PosNo NO-LOCK NO-ERROR.
            IF NOT AVAILABLE ttState THEN NEXT.

            FIND ttMatQ WHERE ttMatQ.PosNo = ttGradOut.PosNo EXCLUSIVE-LOCK NO-ERROR.
            IF NOT AVAILABLE ttMatQ THEN NEXT.

            /* dOut is the gradient from the next layer */
            DO k = 1 TO {&EMBEDDING_SIZE}:
                dOut[k] = ttGradOut.Weight[k].
            END.

            /* Zero initialize dQ and dK */
            DO k = 1 TO {&EMBEDDING_SIZE}:
                dQ[k] = 0.
                dK[k] = 0.
            END.

            /* Compute gradients for V and accumulate for K and Q */
            FOR EACH ttStatePars WHERE ttStatePars.PosNo = ttGradOut.PosNo NO-LOCK BY ttStatePars.IdxNo:

                j = ttStatePars.IdxNo.

                /* Find K/V record by stored KVPosNo */
                FIND ttMatKV WHERE ttMatKV.PosNo = ttStatePars.PosNo EXCLUSIVE-LOCK NO-ERROR.
                IF NOT AVAILABLE ttMatKV THEN NEXT.

                /* Gradient w.r.t. V: dV = attn * dOut */
                DO k = 1 TO {&EMBEDDING_SIZE}:
                    dV[k] = ttState.AttnWeight[j] * dOut[k].
                    /* Update V */
                    ttMatKV.V[k] = ttMatKV.V[k] - THIS-OBJECT:learningRate * dV[k].
                END.

                /* Compute dot product of dOut and V */
                dotProd = 0.
                DO k = 1 TO {&EMBEDDING_SIZE}:
                    dotProd = dotProd + dOut[k] * ttStatePars.V[k].
                END.

                /* delta = attn * (dotProd * scaleFactor) */
                delta = ttState.AttnWeight[j] * (dotProd * scaleFactor).

                /* Accumulate dQ and dK */
                DO k = 1 TO {&EMBEDDING_SIZE}:
                    dQ[k] = dQ[k] + delta * ttStatePars.K[k].
                    dK[k] = dK[k] + delta * ttState.Q[k].
                END.

                /* Update K */
                DO k = 1 TO {&EMBEDDING_SIZE}:
                    ttMatKV.K[k] = ttMatKV.K[k] - learningRate * dK[k].
                END.

            END.

            /* Update Q */
            DO k = 1 TO {&EMBEDDING_SIZE}:
                ttMatQ.Q[k] = ttMatQ.Q[k] - learningRate * dQ[k].
            END.

        END.

        /* Serialize persisted context embedding */
        TEMP-TABLE ttPersistedContextEmbedding:WRITE-JSON("longchar", lcOutput, TRUE).

        /* Re-run forward with original embeddings */
        RETURN THIS-OBJECT:forward(lcOutput).

    END METHOD.
     
 /*****
     METHOD PUBLIC OVERRIDE LONGCHAR backward(INPUT lcGradient AS LONGCHAR):
        DEFINE VARIABLE lcOutput    AS LONGCHAR NO-UNDO.
        DEFINE VARIABLE i           AS INTEGER  NO-UNDO.
        DEFINE VARIABLE k           AS INTEGER  NO-UNDO.
        DEFINE VARIABLE gradWeight  AS DECIMAL  EXTENT {&EMBEDDING_SIZE}.
        DEFINE BUFFER ttGrad FOR ttContextEmbeddingTemp.
        DEFINE BUFFER ttPrev FOR ttContextEmbedding.
        DEFINE BUFFER ttState FOR ttAttentionState.
        DEFINE BUFFER ttPars  FOR ttAttentionStatePars.
        DEFINE BUFFER ttMat   FOR ttAttentionMatrix.

        TEMP-TABLE ttContextEmbeddingTemp:READ-JSON("LONGCHAR", lcGradient, "empty").

        /* For each token, compute the contribution to attention weight updates */
        FOR EACH ttGrad NO-LOCK:
            /* Recreate attention output gradient at position */
            gradWeight = ttGrad.Weight.

            /* Fetch attention state for current PosNo */
            FIND FIRST ttState WHERE ttState.PosNo = ttGrad.PosNo NO-ERROR.
            IF NOT AVAILABLE ttState THEN NEXT.

            /* Update Q in AttentionMatrix */
            FIND FIRST ttMat WHERE ttMat.PosNo = ttGrad.PosNo NO-ERROR.
            IF AVAILABLE ttMat THEN DO:
                DO i = 1 TO {&EMBEDDING_SIZE}:
                    ttMat.Q[i] = ttMat.Q[i] - gradWeight[i].
                END.
            END.

            /* Backpropagate to keys and values */
            FOR EACH ttPars WHERE ttPars.PosNo = ttGrad.PosNo NO-LOCK:
                FIND FIRST ttMat WHERE ttMat.PosNo = ttPars.IdxNo NO-ERROR.
                IF AVAILABLE ttMat THEN DO:
                    /* Value update (for ttPars.V[]) */
                    DO i = 1 TO {&EMBEDDING_SIZE}:
                        ttMat.V[i] = ttMat.V[i] - (ttPars.AttentionWeight * gradWeight[i]).
                    END.

                    /* Key update (approximation, using symmetric assumption with Q) */
                    /* Optional: you can use ttState.Q or re-derive Q from ttMat.Q */
                    DO i = 1 TO {&EMBEDDING_SIZE}:
                        ttMat.K[i] = ttMat.K[i] - gradWeight[i].
                    END.
                END.
            END.

            /* Reconstruct gradient for previous layer */
            CREATE ttContextEmbedding.
            ASSIGN
                ttContextEmbedding.PosNo   = ttGrad.PosNo
                ttContextEmbedding.TokenId = ttGrad.TokenId.
            DO i = 1 TO {&EMBEDDING_SIZE}:
                ttContextEmbedding.Weight[i] = gradWeight[i]. /* Can be improved with full backprop formula */
            END.
        END.

        TEMP-TABLE ttContextEmbedding:WRITE-JSON("LONGCHAR", lcOutput, TRUE).
        RETURN lcOutput.
    END METHOD.

 
 *****/
 /****
    METHOD PUBLIC OVERRIDE LONGCHAR backward(INPUT lcGradient AS LONGCHAR):
        DEFINE VARIABLE lcOutput    AS LONGCHAR NO-UNDO.
        DEFINE VARIABLE i           AS INTEGER  NO-UNDO.
        DEFINE VARIABLE k           AS INTEGER  NO-UNDO.
        DEFINE VARIABLE gradWeight  AS DECIMAL  EXTENT {&EMBEDDING_SIZE}.
        DEFINE BUFFER ttGrad FOR ttContextEmbeddingTemp.
        DEFINE BUFFER ttPrev FOR ttContextEmbedding.
        DEFINE BUFFER ttState FOR ttAttentionState.
        DEFINE BUFFER ttPars  FOR ttAttentionStatePars.
        DEFINE BUFFER ttMat   FOR ttAttentionMatrix.

        TEMP-TABLE ttContextEmbeddingTemp:READ-JSON("LONGCHAR", lcGradient, "empty").

        /* For each token, compute the contribution to attention weight updates */
        FOR EACH ttGrad NO-LOCK:
            /* Recreate attention output gradient at position */
            gradWeight = ttGrad.Weight.

            /* Fetch attention state for current PosNo */
            FIND FIRST ttState WHERE ttState.PosNo = ttGrad.PosNo NO-ERROR.
            IF NOT AVAILABLE ttState THEN NEXT.

            /* Update Q in AttentionMatrix */
            FIND FIRST ttMat WHERE ttMat.PosNo = ttGrad.PosNo NO-ERROR.
            IF AVAILABLE ttMat THEN DO:
                DO i = 1 TO {&EMBEDDING_SIZE}:
                    ttMat.Q[i] = ttMat.Q[i] - gradWeight[i].
                END.
            END.

            /* Backpropagate to keys and values */
            FOR EACH ttPars WHERE ttPars.PosNo = ttGrad.PosNo NO-LOCK:
                FIND FIRST ttMat WHERE ttMat.PosNo = ttPars.IdxNo NO-ERROR.
                IF AVAILABLE ttMat THEN DO:
                    /* Value update (for ttPars.V[]) */
                    DO i = 1 TO {&EMBEDDING_SIZE}:
                        ttMat.V[i] = ttMat.V[i] - (ttPars.AttentionWeight * gradWeight[i]).
                    END.

                    /* Key update (approximation, using symmetric assumption with Q) */
                    /* Optional: you can use ttState.Q or re-derive Q from ttMat.Q */
                    DO i = 1 TO {&EMBEDDING_SIZE}:
                        ttMat.K[i] = ttMat.K[i] - gradWeight[i].
                    END.
                END.
            END.

            /* Reconstruct gradient for previous layer */
            CREATE ttContextEmbedding.
            ASSIGN
                ttContextEmbedding.PosNo   = ttGrad.PosNo
                ttContextEmbedding.TokenId = ttGrad.TokenId.
            DO i = 1 TO {&EMBEDDING_SIZE}:
                ttContextEmbedding.Weight[i] = gradWeight[i]. /* Can be improved with full backprop formula */
            END.
        END.

        TEMP-TABLE ttContextEmbedding:WRITE-JSON("LONGCHAR", lcOutput, TRUE).
        RETURN lcOutput.
   END METHOD.
*****/
 
 /************************************   
    METHOD PUBLIC OVERRIDE LONGCHAR backward(INPUT lcGradient AS LONGCHAR):
        DEFINE VARIABLE i AS INTEGER NO-UNDO.

        /* Deserialize incoming gradient into temporary context embedding */
        TEMP-TABLE ttContextEmbeddingTemp:READ-JSON("LONGCHAR", lcGradient, "empty").

        /* Apply gradient updates only to V vectors in ttAttentionMatrix */
        FOR EACH ttContextEmbeddingTemp:
            FIND FIRST ttAttentionMatrix WHERE ttAttentionMatrix.PosNo = ttContextEmbeddingTemp.PosNo NO-ERROR.
            IF AVAILABLE ttAttentionMatrix THEN
            DO i = 1 TO {&EMBEDDING_SIZE}:
                ttAttentionMatrix.V[i] = ttAttentionMatrix.V[i] - ttContextEmbeddingTemp.Weight[i].
            END.
        END.

        /* Return the same gradient back for further backward propagation */
        RETURN lcGradient.
   END METHOD.
*******************************/   
   
    
END CLASS.
