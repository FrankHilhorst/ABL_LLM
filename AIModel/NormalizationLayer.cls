USING Progress.Json.ObjectModel.JsonObject.
USING AIModel.Layer.

USING Progress.Json.ObjectModel.JsonObject.
USING Progress.Json.ObjectModel.ObjectModelParser.
USING AIModel.Layer.

CLASS AIModel.NormalizationLayer INHERITS AIModel.Layer:

    //DEFINE VARIABLE LearningRate AS DECIMAL     NO-UNDO INIT 0.01.
    {AIModel/LayerSharedDefs.i}

    /* Input/output temp-table */
    DEFINE TEMP-TABLE ttContextEmbeddingTemp NO-UNDO SERIALIZE-NAME "ttContextEmbedding" LIKE ttContextEmbedding.
    
    DEFINE TEMP-TABLE ttNormStats NO-UNDO
        FIELD ColNo   AS INTEGER
        FIELD Mean    AS DECIMAL
        FIELD Stddev  AS DECIMAL.
        
    DEFINE TEMP-TABLE ttNormState NO-UNDO
        FIELD PosNo   AS INTEGER
        FIELD TokenId AS INTEGER
        FIELD NormPreScale AS DECIMAL EXTENT {&EMBEDDING_SIZE}. /* normalized but before scale & shift */

    /* Learnable parameters for scale (gamma) and shift (beta) */
    DEFINE TEMP-TABLE ttAdjustment NO-UNDO
        FIELD Scale AS DECIMAL EXTENT {&EMBEDDING_SIZE}
        FIELD Shift AS DECIMAL EXTENT {&EMBEDDING_SIZE}.
        
    DEFINE TEMP-TABLE ttGradAcc NO-UNDO
        FIELD ColNo     AS INTEGER
        FIELD GradScale AS DECIMAL
        FIELD GradShift AS DECIMAL.
       
    CONSTRUCTOR PUBLIC NormalizationLayer(iLayerNo AS INT,iLayerCode AS CHAR, ihCallingProc AS HANDLE):  
        SUPER(iLayerNo,iLayerCode,ihCallingProc).
    END CONSTRUCTOR.

    /* Initialize weights: gamma = 1, beta = 0 */
    METHOD PUBLIC OVERRIDE VOID InitializeWeights():
        DEFINE VARIABLE i AS INTEGER NO-UNDO.
        CREATE ttAdjustment.
        DO i = 1 TO {&EMBEDDING_SIZE}:
            ASSIGN 
                ttAdjustment.Scale[i] = 1.0
                ttAdjustment.Shift[i] = 0.0.
        END.
    END METHOD.
    
    METHOD PRIVATE VOID CalcAvgAndStddev (
        INPUT  iColNo     AS INTEGER,
        OUTPUT dAvg       AS DECIMAL,
        OUTPUT dStdDev    AS DECIMAL
    ):
        DEFINE VARIABLE dSum     AS DECIMAL     NO-UNDO.
        DEFINE VARIABLE dSqSum   AS DECIMAL     NO-UNDO.
        DEFINE VARIABLE dMean    AS DECIMAL     NO-UNDO.
        DEFINE VARIABLE dVar     AS DECIMAL     NO-UNDO.
        DEFINE VARIABLE dCount   AS DECIMAL     NO-UNDO.

        dSum   = 0.
        dSqSum = 0.
        dCount = 0.

        FOR EACH ttContextEmbeddingTemp:
            dSum   = dSum   + ttContextEmbeddingTemp.Weight[iColNo].
            dSqSum = dSqSum + EXP(ttContextEmbeddingTemp.Weight[iColNo],2).
            dCount = dCount + 1.
        END.

        IF dCount > 0 THEN DO:
            dMean   = dSum / dCount.
            dVar    = (dSqSum / dCount) - EXP(dMean,2).
            dAvg    = dMean.
            dStdDev = SQRT(MAXIMUM(dVar, 0.0000001)). /* avoid divide-by-zero or negative sqrt */
        END.
        ELSE DO:
            dAvg    = 0.
            dStdDev = 1.
        END.
    END METHOD.
    
    METHOD PUBLIC OVERRIDE JsonObject serialize():
        DEFINE VARIABLE oJson AS JsonObject NO-UNDO.
        oJson = NEW JsonObject().
        TEMP-TABLE ttAdjustment:WRITE-JSON("JSONOBJECT", oJson, TRUE).
        RETURN oJson.
    END METHOD.

    METHOD PUBLIC OVERRIDE VOID deserialize(INPUT oJson AS JsonObject):
        TEMP-TABLE ttAdjustment:READ-JSON("JSONOBJECT", oJson, "empty").
    END METHOD.
    
    METHOD PUBLIC OVERRIDE LONGCHAR forward(INPUT lcInput AS LONGCHAR):
        DEFINE VARIABLE i        AS INTEGER     NO-UNDO.
        DEFINE VARIABLE dMean    AS DECIMAL     NO-UNDO.
        DEFINE VARIABLE dStddev  AS DECIMAL     NO-UNDO.
        DEFINE VARIABLE lcOutput AS LONGCHAR    NO-UNDO.

        EMPTY TEMP-TABLE ttContextEmbeddingTemp.
        TEMP-TABLE ttContextEmbeddingTemp:READ-JSON("longchar", lcInput, "EMPTY").
        EMPTY TEMP-TABLE ttNormStats.
        EMPTY TEMP-TABLE ttNormState.

        DO i = 1 TO {&EMBEDDING_SIZE}:
            THIS-OBJECT:CalcAvgAndStddev(i, OUTPUT dMean, OUTPUT dStddev).

            CREATE ttNormStats.
            ASSIGN ttNormStats.ColNo  = i
                   ttNormStats.Mean   = dMean
                   ttNormStats.Stddev = dStddev.
        END.

        FOR EACH ttContextEmbeddingTemp:
            CREATE ttNormState.
            ASSIGN ttNormState.PosNo   = ttContextEmbeddingTemp.PosNo
                   ttNormState.TokenId = ttContextEmbeddingTemp.TokenId.

            DO i = 1 TO {&EMBEDDING_SIZE}:
                FIND ttNormStats WHERE ttNormStats.ColNo = i NO-ERROR.
                IF NOT AVAILABLE ttNormStats THEN NEXT.

                /* Normalize */
                ttNormState.NormPreScale[i] = (ttContextEmbeddingTemp.Weight[i] - ttNormStats.Mean) / ttNormStats.Stddev.

                /* Apply scale and shift (Y and B) */
                ttContextEmbeddingTemp.Weight[i] = 
                    ttNormState.NormPreScale[i] * ttAdjustment.Scale[i] + ttAdjustment.Shift[i].
            END.
        END.

        THIS-OBJECT:cloneContextEmbedding(INPUT BUFFER ttContextEmbeddingTemp:HANDLE,
                                          INPUT BUFFER ttPersistedContextEmbedding:HANDLE).

        TEMP-TABLE ttContextEmbeddingTemp:WRITE-JSON("longchar", lcOutput, TRUE).

TEMP-TABLE ttContextEmbeddingTemp:WRITE-JSON("file",SUBST("c:\temp\ttContextEmbeddingTemp_F_&1_&2.json",
                                                           THIS-OBJECT:LayerCode,THIS-OBJECT:LayerNo), TRUE).        
        RETURN lcOutput.
    END METHOD.

    METHOD PUBLIC OVERRIDE LONGCHAR backward(INPUT lcGradOutput AS LONGCHAR):
        DEFINE VARIABLE i        AS INTEGER     NO-UNDO.
        DEFINE VARIABLE dOutput  AS DECIMAL     NO-UNDO.
        DEFINE VARIABLE dTarget  AS DECIMAL     NO-UNDO.
        DEFINE VARIABLE dInput   AS DECIMAL     NO-UNDO.
        DEFINE VARIABLE dDelta   AS DECIMAL     NO-UNDO.
        DEFINE VARIABLE dGradS   AS DECIMAL     NO-UNDO.
        DEFINE VARIABLE dGradB   AS DECIMAL     NO-UNDO.
        DEFINE VARIABLE lcOutput AS LONGCHAR    NO-UNDO.
        DEFINE VARIABLE count    AS INTEGER     NO-UNDO.

        EMPTY TEMP-TABLE ttContextEmbeddingTemp.
        TEMP-TABLE ttContextEmbeddingTemp:READ-JSON("longchar", lcGradOutput, "EMPTY").

        EMPTY TEMP-TABLE ttGradAcc.
        
        /* Accumulate gradients for Scale and Shift */
        FOR EACH ttContextEmbeddingTemp:
            FIND ttPersistedContextEmbedding WHERE
                ttPersistedContextEmbedding.PosNo   = ttContextEmbeddingTemp.PosNo AND
                ttPersistedContextEmbedding.TokenId = ttContextEmbeddingTemp.TokenId NO-ERROR.

            FIND ttNormState WHERE
                ttNormState.PosNo = ttContextEmbeddingTemp.PosNo AND
                ttNormState.TokenId = ttContextEmbeddingTemp.TokenId NO-ERROR.

            IF NOT AVAIL ttPersistedContextEmbedding OR NOT AVAIL ttNormState THEN NEXT.

            DO i = 1 TO {&EMBEDDING_SIZE}:
                dTarget  = ttContextEmbeddingTemp.Weight[i].
                dOutput  = ttPersistedContextEmbedding.Weight[i].
                dInput   = ttNormState.NormPreScale[i].

                dDelta   = dOutput - dTarget.

                /* Gradient for scale (Y) and shift (B) */
                dGradS = dDelta * dInput.
                dGradB = dDelta.

                FIND ttGradAcc WHERE ttGradAcc.ColNo = i NO-ERROR.
                IF NOT AVAILABLE ttGradAcc THEN DO:
                    CREATE ttGradAcc.
                    ASSIGN ttGradAcc.ColNo     = i
                           ttGradAcc.GradScale = dGradS
                           ttGradAcc.GradShift = dGradB.
                END.
                ELSE DO:
                    ASSIGN ttGradAcc.GradScale = ttGradAcc.GradScale + dGradS
                           ttGradAcc.GradShift = ttGradAcc.GradShift + dGradB.
                END.
            END.
        END.

        /* Apply updates to adjustment table using averaged gradients */
        count = EXTENT(ttContextEmbeddingTemp.Weight).

        FOR EACH ttGradAcc:
            ttAdjustment.Scale[ttGradAcc.ColNo] = ttAdjustment.Scale[ttGradAcc.ColNo] -
                (THIS-OBJECT:LearningRate * ttGradAcc.GradScale / count).

            ttAdjustment.Shift[ttGradAcc.ColNo] = ttAdjustment.Shift[ttGradAcc.ColNo] -
                (THIS-OBJECT:LearningRate * ttGradAcc.GradShift / count).
        END.

        /* Optionally: reverse transformation if required downstream */
        TEMP-TABLE ttContextEmbeddingTemp:WRITE-JSON("longchar", lcOutput, TRUE).
        RETURN lcOutput.
    END METHOD.
    


END CLASS.
