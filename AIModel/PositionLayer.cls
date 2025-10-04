USING Progress.Json.ObjectModel.JsonObject.
USING AIModel.Layer.

USING Progress.Json.ObjectModel.JsonObject.
USING AIModel.Layer.

CLASS AIModel.PositionLayer INHERITS Layer:

    {AIModel/LayerSharedDefs.i}
    
    DEFINE TEMP-TABLE ttContextEmbeddingTemp NO-UNDO SERIALIZE-NAME "ttContextEmbedding" LIKE ttContextEmbedding.
    
    /* Positional embeddings — weights are learned per position */
    DEFINE TEMP-TABLE ttPositionalMatrix NO-UNDO
        FIELD PosNo  AS INTEGER
        FIELD Weight AS DECIMAL EXTENT {&EMBEDDING_SIZE}.
       
    /* Constructor */
    CONSTRUCTOR PUBLIC PositionLayer(iLayerNo AS INT,iLayerCode AS CHAR, ihCallingProc AS HANDLE):  
        SUPER(iLayerNo,iLayerCode,ihCallingProc).
    END CONSTRUCTOR.

    /* Initialize positional weights randomly */
    METHOD PUBLIC OVERRIDE VOID initializeWeights():
        DEFINE VARIABLE i        AS INTEGER NO-UNDO.
        DEFINE VARIABLE j        AS INTEGER NO-UNDO.
        DEFINE VARIABLE randVal  AS DECIMAL NO-UNDO.

        DO i = 1 TO {&MAX_SEQUENCE_LENGTH}:  /* Max sequence length */
            CREATE ttPositionalMatrix.
            ASSIGN ttPositionalMatrix.PosNo = i.

            DO j = 1 TO EXTENT(ttPositionalMatrix.Weight):
                randVal = (RANDOM(0, 1000) / 1000) * 0.02 - 0.01.
                ttPositionalMatrix.Weight[j] = randVal.
            END.
        END.
    END METHOD.

    /* Serialize ttPositionalMatrix to JSON */
    METHOD PUBLIC OVERRIDE JsonObject serialize():
        DEFINE VARIABLE oJson   AS JsonObject NO-UNDO.
        oJson = NEW JsonObject().
        TEMP-TABLE ttPositionalMatrix:WRITE-JSON("JsonObject", oJson, TRUE).
        RETURN oJson.
    END METHOD.

    /* Deserialize JSON into ttPositionalMatrix */
    METHOD PUBLIC OVERRIDE VOID deserialize(INPUT oJson AS JsonObject):
        TEMP-TABLE ttPositionalMatrix:READ-JSON("JsonObject", oJson, "empty").
    END METHOD.

    METHOD PUBLIC OVERRIDE LONGCHAR forward ( INPUT lcInput AS LONGCHAR):

        DEFINE VARIABLE i AS INTEGER NO-UNDO.
        DEFINE VARIABLE d AS INTEGER NO-UNDO.
        DEFINE VARIABLE lcOutput AS LONGCHAR   NO-UNDO.

        FIX-CODEPAGE(lcOutput) = "UTF-8".
        
        EMPTY TEMP-TABLE ttContextEmbeddingTemp.
        TEMP-TABLE ttContextEmbeddingTemp:READ-JSON("longchar", lcInput, "EMPTY").

TEMP-TABLE ttContextEmbeddingTemp:WRITE-JSON("file",SUBST("c:\temp\ttContextEmbeddingTemp_FS_&1_&2.json",
                                                           THIS-OBJECT:LayerCode,THIS-OBJECT:LayerNo), TRUE).        
        
        FOR EACH ttContextEmbeddingTemp:
            FIND ttPositionalMatrix WHERE ttPositionalMatrix.PosNo = ttContextEmbeddingTemp.PosNo NO-ERROR.
            IF AVAILABLE ttPositionalMatrix THEN DO:
                /* Elementwise addition of position embedding into context embedding */
                DO d = 1 TO {&EMBEDDING_SIZE}:
                    ttContextEmbeddingTemp.Weight[d] = ttContextEmbeddingTemp.Weight[d] 
                                                 + ttPositionalMatrix.Weight[d].
                END.
            END.
        END.
        TEMP-TABLE ttContextEmbeddingTemp:WRITE-JSON("longchar", lcOutput, TRUE).

TEMP-TABLE ttContextEmbeddingTemp:WRITE-JSON("file",SUBST("c:\temp\ttContextEmbeddingTemp_FE_&1_&2.json",
                                                           THIS-OBJECT:LayerCode,THIS-OBJECT:LayerNo), TRUE).        
        RETURN lcOutput.

    END METHOD.
   
    
    /* Forward pass: add positional embeddings to token embeddings */
    METHOD PUBLIC OVERRIDE LONGCHAR backward(INPUT lcGradient AS LONGCHAR):

        DEFINE VARIABLE lcOutput AS LONGCHAR NO-UNDO.
        DEFINE VARIABLE i        AS INTEGER   NO-UNDO.

        EMPTY TEMP-TABLE ttContextEmbedding.
        TEMP-TABLE ttContextEmbedding:READ-JSON("LONGCHAR", lcGradient, "empty").

        /* Update positional matrix using PosNo */
        FOR EACH ttContextEmbedding:
            FIND FIRST ttPositionalMatrix WHERE ttPositionalMatrix.PosNo = ttContextEmbedding.PosNo NO-ERROR.
            IF AVAILABLE ttPositionalMatrix THEN
                DO i = 1 TO EXTENT(ttPositionalMatrix.Weight):
                    ttPositionalMatrix.Weight[i] = ttPositionalMatrix.Weight[i] - ttContextEmbedding.Weight[i].
                END.
        END.

        /* Now generate gradient for the embedding layer by reusing same structure, grouping by TokenId */
        TEMP-TABLE ttContextEmbedding:WRITE-JSON("LONGCHAR", lcOutput, TRUE).
        RETURN lcOutput.
    END METHOD.
 
 /************************
    METHOD PRIVATE VOID computeGradient(INPUT TABLE ttTargetPositionalMatrix):
        DEFINE VARIABLE i        AS INTEGER NO-UNDO.
        DEFINE VARIABLE lcOutput AS LONGCHAR   NO-UNDO.

        FOR EACH ttTargetPositionalMatrix:
            FIND FIRST ttPositionalMatrix WHERE ttPositionalMatrix.PosNo = ttTargetPositionalMatrix.PosNo NO-ERROR.
            IF AVAILABLE ttPositionalMatrix THEN DO:
                DO i = 1 TO EXTENT(ttPositionalMatrix.Weight):
                    ttPositionalMatrix.Weight[i] = ttPositionalMatrix.Weight[i] - ttTargetPositionalMatrix.Weight[i].
                END.
            END.
        END.
    END METHOD.
**************************/    
 
END CLASS.
