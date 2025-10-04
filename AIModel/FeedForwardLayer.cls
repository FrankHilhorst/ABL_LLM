USING Progress.Json.ObjectModel.JsonObject.
USING AIModel.Layer.

USING Progress.Json.ObjectModel.JsonObject.
USING Progress.Json.ObjectModel.ObjectModelParser.

CLASS AIModel.FeedForwardLayer INHERITS Layer:

    {AIModel/LayerSharedDefs.i}
    
//  DEFINE VARIABLE LearningRate AS DECIMAL     NO-UNDO INIT 0.01.     
    DEFINE VARIABLE Counter      AS INTEGER     NO-UNDO.

    DEFINE TEMP-TABLE ttContextEmbeddingTemp NO-UNDO SERIALIZE-NAME "ttContextEmbedding" LIKE ttContextEmbedding.
    DEFINE TEMP-TABLE ttPersistedOutput      NO-UNDO LIKE ttContextEmbedding.
    
    DEFINE TEMP-TABLE ttOutput               NO-UNDO SERIALIZE-NAME "ttContextEmbeddingTemp" LIKE ttContextEmbeddingTemp .

    //DEFINE TEMP-TABLE ttPersistedContextEmbedding  NO-UNDO LIKE ttContextEmbeddingTemp.

    DEFINE TEMP-TABLE ttContextEmbeddingFF NO-UNDO LIKE ttContextEmbeddingTemp.    
//     FIELD FFW1_Weight  AS DECIMAL EXTENT {&FF_DIM}      
//     FIELD FFW2_Weight  AS DECIMAL EXTENT {&EMBEDDING_SIZE}
//     FIELD FFB1_Bias    AS DECIMAL EXTENT {&FF_DIM}
//     FIELD FFB2_Bias    AS DECIMAL EXTENT {&EMBEDDING_SIZE}.
    
    DEFINE TEMP-TABLE ttFF1 NO-UNDO
       FIELD iRow      AS INT 
       FIELD Weight    AS DECIMAL EXTENT {&FF_DIM}      
       FIELD Bias      AS DECIMAL EXTENT {&FF_DIM}
       .
       
    DEFINE TEMP-TABLE ttFF2 NO-UNDO
       FIELD iRow      AS INT 
       FIELD Weight    AS DECIMAL EXTENT {&EMBEDDING_SIZE}
       FIELD Bias      AS DECIMAL EXTENT {&EMBEDDING_SIZE}.

    CONSTRUCTOR PUBLIC FeedForwardLayer(iLayerNo AS INT,iLayerCode AS CHAR, ihCallingProc AS HANDLE):  
        SUPER(iLayerNo,iLayerCode,ihCallingProc).
    END CONSTRUCTOR.
       
    METHOD PUBLIC OVERRIDE VOID initializeWeights():
       DEFINE VARIABLE i AS INTEGER     NO-UNDO.
       DEFINE VARIABLE j AS INTEGER     NO-UNDO.
       DO i = 1 TO {&EMBEDDING_SIZE}:
          CREATE ttFF1.
          ASSIGN ttFF1.iRow = i.
          DO j = 1 TO EXTENT(ttFF1.Weight):
             ASSIGN ttFF1.Weight[j] = RANDOM(-50, 50) / 100.0
                    ttFF1.Bias[j]   = 0.
          END.
       END.
       DO i = 1 TO {&FF_DIM}:
          CREATE ttFF2.
          ASSIGN ttFF2.iRow = i.
          DO j = 1 TO EXTENT(ttFF2.Weight):
             ASSIGN ttFF2.Weight[j] = RANDOM(-50, 50) / 100.0
                    ttFF2.Bias[j]   = 0.
          END.
       END.

    END METHOD.
    
    METHOD PUBLIC OVERRIDE JsonObject serialize():
       DEF VAR oJson     AS JsonObject NO-UNDO.
       DEF VAR oJsonTbl  AS JsonObject NO-UNDO.
       oJson = NEW JsonObject().
       oJsonTbl = NEW JsonObject().       
       TEMP-TABLE ttFF1:WRITE-JSON("JsonObject",oJsonTbl,TRUE). 
       oJson:ADD("ttFF1",oJsonTbl).
       oJsonTbl = NEW JsonObject().       
       TEMP-TABLE ttFF2:WRITE-JSON("JsonObject",oJsonTbl,TRUE). 
       oJson:ADD("ttFF2",oJsonTbl).       
       RETURN oJson.
    END METHOD. 
    
    METHOD PUBLIC OVERRIDE VOID deserialize(INPUT oJson AS JsonObject):
        DEF VAR oTtFF1   AS JsonObject        NO-UNDO.
        DEF VAR oTtFF2   AS JsonObject        NO-UNDO.
        ASSIGN oTtFF1 = oJson:getJsonObject("ttFF1")
               oTtFF2 = oJson:getJsonObject("ttFF2").
        TEMP-TABLE ttFF1:READ-JSON("JsonObject",oTtFF1,"empty").
        TEMP-TABLE ttFF2:READ-JSON("JsonObject",oTtFF2,"empty").
    END METHOD.

    METHOD PUBLIC OVERRIDE LONGCHAR forward(INPUT lcInput AS LONGCHAR):
        DEFINE VARIABLE i        AS INTEGER     NO-UNDO.
        DEFINE VARIABLE j        AS INTEGER     NO-UNDO.
        DEFINE VARIABLE lcOutput AS LONGCHAR    NO-UNDO.
        EMPTY TEMP-TABLE ttContextEmbeddingTemp.
        EMPTY TEMP-TABLE ttOutput.
        TEMP-TABLE ttContextEmbeddingTemp:READ-JSON("longchar", lcInput, "empty").

        DEF BUFFER     bInput       FOR  ttContextEmbeddingTemp.
        DEF BUFFER     bOutput      FOR ttOutput.
        THIS-OBJECT:Counter = THIS-OBJECT:Counter + 1.
        
        TEMP-TABLE ttContextEmbeddingTemp:WRITE-JSON("file",SUBST("C:\temp\ttContextEmbeddingTemp_&1.json",THIS-OBJECT:Counter),TRUE).
        EMPTY TEMP-TABLE ttOutput.
        FOR EACH bInput:
            DO i = 1 TO {&FF_DIM}:
                bInput.HiddenPreActivation[i] = 0.
                FOR EACH ttFF1:
                    bInput.HiddenPreActivation[i] = bInput.HiddenPreActivation[i]
                                                   + bInput.Weight[ttFF1.iRow] * ttFF1.Weight[i].
                    bInput.HiddenPreActivation[i] = bInput.HiddenPreActivation[i] + ttFF1.Bias[i].
                    bInput.reluWeight[i] = MAXIMUM(bInput.HiddenPreActivation[i], 0).
                END.
            END.

            CREATE bOutput.
            ASSIGN bOutput.PosNo   = bInput.PosNo
                   bOutput.TokenId = bInput.TokenId.

            DO i = 1 TO {&EMBEDDING_SIZE}:
                bOutput.Weight[i] = 0.
                FOR EACH ttFF2:
                    bOutput.Weight[i] = bOutput.Weight[i]
                                       + bInput.reluWeight[ttFF2.iRow] * ttFF2.Weight[i].
                    bOutput.Weight[i] = bOutput.Weight[i] + ttFF2.Bias[i].
                END.    
            END.
        END.
        
         //ttPersistedContextEmbedding  NO-UNDO LIKE ttContextEmbeddingTemp.
        THIS-OBJECT:cloneContextEmbedding(INPUT BUFFER ttContextEmbeddingTemp:HANDLE,
                                          INPUT BUFFER ttPersistedContextEmbedding:HANDLE).
                   
                 
        TEMP-TABLE ttOutput:WRITE-JSON("file",SUBST("C:\temp\ttOutput_FE_&1_&2.json",THIS-OBJECT:LayerCode,THIS-OBJECT:LayerNo),TRUE).
        EMPTY TEMP-TABLE ttPersistedOutput.    
        THIS-OBJECT:cloneContextEmbedding(INPUT BUFFER ttOutput:HANDLE,
                                          INPUT BUFFER ttPersistedOutput:HANDLE).
TEMP-TABLE ttPersistedOutput:WRITE-JSON("file",SUBST("C:\temp\ttPersistedOutput_FE_&1_&2.json",
                                                      THIS-OBJECT:LayerCode,THIS-OBJECT:LayerNo),TRUE).

TEMP-TABLE ttContextEmbeddingTemp:WRITE-JSON("file",SUBST("c:\temp\ttContextEmbeddingTemp_FE_&1_&2.json",
                                                           THIS-OBJECT:LayerCode,THIS-OBJECT:LayerNo), TRUE).        
        TEMP-TABLE ttOutput:WRITE-JSON("longchar", lcOutput, TRUE).
        RETURN lcOutput.
       
    END METHOD.
    
    METHOD PUBLIC OVERRIDE LONGCHAR backward(INPUT lcGradOutput AS LONGCHAR):
        DEFINE VARIABLE i         AS INTEGER     NO-UNDO.
        DEFINE VARIABLE dWeight   AS DECIMAL     NO-UNDO.
        DEFINE VARIABLE dBias     AS DECIMAL     NO-UNDO.
        DEFINE VARIABLE lcJson    AS LONGCHAR    NO-UNDO.
        DEFINE VARIABLE lcPayload AS LONGCHAR    NO-UNDO.
        FIX-CODEPAGE(lcPayload) = "UTF-8".
        EMPTY TEMP-TABLE ttContextEmbeddingTemp.        
        TEMP-TABLE ttContextEmbeddingTemp:READ-JSON("longchar", lcGradOutput, "EMPTY").
        
TEMP-TABLE ttContextEmbeddingTemp:WRITE-JSON("file",SUBST("c:\temp\ttContextEmbeddingTemp_BS_&1_&2.json",
                                             THIS-OBJECT:LayerCode,THIS-OBJECT:LayerNo),TRUE). 
        
TEMP-TABLE ttPersistedOutput:WRITE-JSON("file",SUBST("c:\temp\ttPersistedOutput_BS_&1_&2.json",
                                          THIS-OBJECT:LayerCode,THIS-OBJECT:LayerNo),TRUE). 
TEMP-TABLE ttPersistedContextEmbedding:WRITE-JSON("file",SUBST("c:\temp\ttPersistedContextEmbedding_BS_&1_&2.json",
                                          THIS-OBJECT:LayerCode,THIS-OBJECT:LayerNo),TRUE).        
                                          
        FOR EACH ttContextEmbeddingTemp:
            FIND ttPersistedContextEmbedding WHERE ttPersistedContextEmbedding.PosNo   = ttContextEmbeddingTemp.posNo AND
                                                   ttPersistedContextEmbedding.TokenId = ttContextEmbeddingTemp.TokenId NO-ERROR.
            FIND ttPersistedOutput WHERE ttPersistedOutput.PosNo = ttContextEmbeddingTemp.posNo AND
                                         ttPersistedOutput.TokenId = ttContextEmbeddingTemp.TokenId NO-ERROR.
 IF NOT AVAIL ttPersistedOutput THEN
 DO:
    MESSAGE "ttContextEmbeddingTemp.posNo" ttContextEmbeddingTemp.posNo SKIP
            "ttContextEmbeddingTemp.TokenId" ttContextEmbeddingTemp.TokenId SKIP
        VIEW-AS ALERT-BOX INFORMATION BUTTONS OK.
     
 END.
            FOR EACH ttFF2:
                DO i = 1 TO {&EMBEDDING_SIZE}:
                    THIS-OBJECT:gradient(
                        INPUT  THIS-OBJECT:LearningRate,
                        INPUT  ttPersistedOutput.reluWeight[ttFF2.iRow],   // dInput
                        INPUT  ttPersistedOutput.Weight[i],                // dOldValue
                        INPUT  ttContextEmbeddingTemp.Weight[i],           // dNewValue
                        INPUT  ttFF2.Weight[i],
                        INPUT  ttFF2.Bias[i],
                        OUTPUT dWeight,
                        OUTPUT dBias
                    ).
                    ASSIGN
                        ttFF2.Weight[i] = dWeight
                        ttFF2.Bias[i]   = dBias.
                END.
            END.                                  
            FOR EACH ttFF1:
                DO i = 1 TO {&FF_DIM}:
                    THIS-OBJECT:gradient(
                        INPUT  THIS-OBJECT:LearningRate,
                        INPUT  ttPersistedContextEmbedding.Weight[ttFF1.iRow],    /* dInput: input neuron */
                        INPUT  ttPersistedOutput.HiddenPreActivation[i],         /* pre-activation */
                        INPUT  ttContextEmbeddingTemp.reluWeight[i],             /* corrected relu output */
                        INPUT  ttFF1.Weight[i],                                  /* weight from input iRow to output i */
                        INPUT  ttFF1.Bias[i],                                    /* bias for output i */
                        OUTPUT dWeight,
                        OUTPUT dBias
                    ).
                    ASSIGN ttFF1.Weight[i] = dWeight
                           ttFF1.Bias[i]   = dBias.
                END.
            END.
        END. /*FOR EACH ttContextEmbeddingTemp:*/
        TEMP-TABLE ttPersistedContextEmbedding:WRITE-JSON("LONGCHAR",lcPayload,TRUE).
        
        RETURN THIS-OBJECT:FORWARD(lcPayload).

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
        DEFINE VARIABLE THIS-OBJECT:LearningRate AS DECIMAL  NO-UNDO INITIAL 0.01.
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
                    ttFF.FFW2_Weight[i] = ttFF.FFW2_Weight[i] - THIS-OBJECT:LearningRate * yGrad[i] * h[j].
                END.
                ttFF.FFB2_Bias[i] = ttFF.FFB2_Bias[i] - THIS-OBJECT:LearningRate * yGrad[i].
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
