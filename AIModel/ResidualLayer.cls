
USING Progress.Lang.*.
USING AIModel.Layer.
USING Progress.Json.ObjectModel.JsonObject.
USING Progress.Json.ObjectModel.ObjectModelParser.

CLASS AIModel.ResidualLayer INHERITS Layer:

    /* Shared definitions like EMBEDDING_SIZE */
    {AIModel/LayerSharedDefs.i}

    DEFINE TEMP-TABLE ttContextEmbeddingTemp NO-UNDO SERIALIZE-NAME "ttContextEmbedding" LIKE ttContextEmbedding.
    
    /* Persisted input (state) */
    DEFINE TEMP-TABLE ttResidualState NO-UNDO
        FIELD PosNo   AS INTEGER
        FIELD TokenId AS INTEGER
        FIELD Weight  AS DECIMAL EXTENT {&EMBEDDING_SIZE}.

    /* Internal state to alternate behavior */
    DEFINE PRIVATE VARIABLE iState AS INTEGER NO-UNDO INITIAL 0.

    CONSTRUCTOR PUBLIC ResidualLayer(iLayerNo AS INT,iLayerCode AS CHAR, ihCallingProc AS HANDLE):  
        SUPER(iLayerNo,iLayerCode,ihCallingProc).
    END CONSTRUCTOR.

    METHOD PUBLIC OVERRIDE VOID initializeWeights():
        /* No weights in residual layer */
    END METHOD.

    METHOD PUBLIC OVERRIDE LONGCHAR forward(INPUT lcInput AS LONGCHAR):
        DEFINE VARIABLE lcOutput AS LONGCHAR NO-UNDO.
        DEFINE VARIABLE i        AS INTEGER     NO-UNDO.
        
        DEFINE BUFFER bInput FOR ttContextEmbeddingTemp.
        DEFINE BUFFER bPersisted FOR ttResidualState.
//MESSAGE STRING(SUBSTR(lcINput,1,25))
//    VIEW-AS ALERT-BOX INFORMATION BUTTONS OK.
       EMPTY TEMP-TABLE ttContextEmbeddingTemp.
       TEMP-TABLE ttContextEmbeddingTemp:READ-JSON("longchar", lcInput, "EMPTY").
TEMP-TABLE ttContextEmbeddingTemp:WRITE-JSON("file",SUBST("c:\temp\ttContextEmbeddingTemp_FS_&1_&2.json",
                                                           THIS-OBJECT:LayerCode,THIS-OBJECT:LayerNo), TRUE).        

        IF iState MODULO 2 = 0 THEN DO:
            /* Persist input */
            FOR EACH bInput:
                CREATE bPersisted.
                ASSIGN
                    bPersisted.PosNo   = bInput.PosNo
                    bPersisted.TokenId = bInput.TokenId
                    bPersisted.Weight  = bInput.Weight.
            END.
        END.
        ELSE DO:
            /* Residual addition: input + persisted */
            FOR EACH bInput:
                FIND bPersisted WHERE bPersisted.PosNo = bInput.PosNo AND
                                      bPersisted.TokenId = bInput.TokenId NO-ERROR.
                IF AVAILABLE bPersisted THEN
                    DO i = 1 TO {&EMBEDDING_SIZE}:
                        bInput.Weight[i] = bInput.Weight[i] + bPersisted.Weight[i].
                    END.
            END.
        END.

        /* Advance state */
        iState = (iState + 1) MODULO 2.

        TEMP-TABLE ttContextEmbeddingTemp:WRITE-JSON("longchar", lcOutput, TRUE).
TEMP-TABLE ttContextEmbeddingTemp:WRITE-JSON("file",SUBST("c:\temp\ttContextEmbeddingTemp_FE_&1_&2.json",
                                                           THIS-OBJECT:LayerCode,THIS-OBJECT:LayerNo), TRUE).        
        RETURN lcOutput.
    END METHOD.

    METHOD PUBLIC OVERRIDE LONGCHAR backward(INPUT lcGradOutput AS LONGCHAR):
        RETURN lcGradOutput.
    END METHOD.

END CLASS.
