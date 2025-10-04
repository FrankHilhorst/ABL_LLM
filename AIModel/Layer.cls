USING Progress.Lang.Object.
USING Progress.Json.ObjectModel.JsonObject.
USING Progress.Json.ObjectModel.JsonArray.
USING Progress.Lang.*.
USING AIModel.*.

CLASS AIModel.Layer:

  {AIModel/LayerSharedDefs.i}
  
  DEFINE PROTECTED PROPERTY OperatingMode AS CHARACTER 
      GET. 
      SET(iOperatingMode AS CHAR):
         IF LOOKUP(iOperatingMode,"TRAIN,PREDICT") = 0 THEN
            UNDO, THROW NEW AppError("Operating Mode must either be 'TRAIN' or 'PREDICT'",-1).
         THIS-OBJECT:OperatingMode = iOperatingMode.   
      END SET.
  
  DEFINE PROTECTED PROPERTY LayerNo   AS INT  GET. SET.
  DEFINE PROTECTED PROPERTY LayerCode AS CHAR GET. SET.
  DEFINE PROTECTED PROPERTY LearningRate AS DEC INIT 0.10 GET. SET.
  DEFINE PROTECTED PROPERTY CallingProc AS HANDLE NO-UNDO GET. SET.  
  
  DEFINE PROTECTED TEMP-TABLE ttEmbeddingsDictionary NO-UNDO
    FIELD TokenId AS INTEGER
    FIELD cToken  AS CHAR
    FIELD Weight  AS DECIMAL EXTENT {&EMBEDDING_SIZE}.
  
  DEFINE PROTECTED TEMP-TABLE ttLogits NO-UNDO
    FIELD PosNo AS INTEGER
    FIELD Logits AS DECIMAL EXTENT {&VOCAB_SIZE}.
  
  DEFINE PROTECTED TEMP-TABLE ttLogitsWeights NO-UNDO
    FIELD EmbeddingIndex AS INTEGER
    FIELD VocabWeights   AS DECIMAL EXTENT {&VOCAB_SIZE}. /* Projection matrix */
  
  
  DEFINE TEMP-TABLE ttLayer NO-UNDO
    FIELD layerNo AS INT
    FIELD layerCode AS CHAR
    FIELD oLayer  AS OBJECT.
 
  CONSTRUCTOR PUBLIC Layer(iLayerNo AS INT, iLayerCode AS CHAR, ihCallingProc AS HANDLE ):
    THIS-OBJECT:LayerNo = iLayerNo.
    THIS-OBJECT:LayerCode = iLayerCode.
    THIS-OBJECT:CallingProc = ihCallingProc.
  END CONSTRUCTOR.
  
  METHOD PUBLIC VOID InitializeLayers(iOPeratingMode AS CHAR):
    THIS-OBJECT:OperatingMode = iOPeratingMode.  
  END METHOD.
  
  METHOD PUBLIC LONGCHAR forward(INPUT lcInput AS LONGCHAR):
  
  END METHOD.
  
  METHOD PUBLIC VOID instantiateTracer ():
  
  END METHOD.
  
  METHOD PUBLIC VOID ResetState():
     EMPTY TEMP-TABLE ttLogits.
  END METHOD.
  
  /* Constructor */

  /* Method: initializeWeights
     Abstract method to be implemented by subclasses to initialize weights. */
  METHOD PUBLIC VOID initializeWeights():
      DEFINE VARIABLE oLayer AS Layer   NO-UNDO.
      FOR EACH ttLayer BY ttLayer.layerNo:
        oLayer = CAST(ttLayer.oLayer,Layer).
        oLayer:initializeWeights().
      END.
    /* No implementation in base class */
  END METHOD.

  /* Method: serialize
     Abstract method to be implemented by subclasses to return layer configuration/state. */
  METHOD PUBLIC JsonObject serialize():
    DEFINE VARIABLE oJsonSerialized AS JsonObject NO-UNDO.
    RETURN oJsonSerialized. /* Placeholder to ensure valid return type */
  END METHOD.
  
  /****
  METHOD PUBLIC JsonObject serialize(icFileName AS CHAR):
     DEFINE VARIABLE oJsonSerialized AS JsonObject NO-UNDO.
     oJsonSerialized = THIS-OBJECT:serialize().
     oJsonSerialized:writeFile(icFileName).
  END METHOD.
  *****/
  /* Method: deserialize
     Abstract method to be implemented by subclasses to receive saved state. */
  METHOD PUBLIC VOID deserialize(INPUT poJson AS JsonObject):
    /* No implementation in base class */
  END METHOD.
  
  METHOD PUBLIC LONGCHAR backward(INPUT lcGradient AS LONGCHAR):
    RETURN lcGradient.
  END METHOD.
  
  METHOD PROTECTED VOID cloneContextEmbedding(INPUT hSource AS HANDLE,
                                            INPUT hClone AS HANDLE):
    DEFINE VARIABLE bSource AS HANDLE      NO-UNDO.  
    DEFINE VARIABLE bClone  AS HANDLE      NO-UNDO.
    DEFINE VARIABLE hQuery  AS HANDLE      NO-UNDO.
    
    CREATE BUFFER bSource FOR TABLE hSource.
    CREATE BUFFER bClone  FOR TABLE hClone.
    
    bClone:TABLE-HANDLE:EMPTY-TEMP-TABLE().
    CREATE QUERY hQuery.
    hQuery:ADD-BUFFER(bSource).
    hQuery:QUERY-PREPARE(SUBST("for each &1",bSource:NAME)).
    hQuery:QUERY-OPEN().
    hQuery:GET-FIRST().
    DO WHILE NOT hQuery:QUERY-OFF-END:
       bClone:BUFFER-CREATE().
       bClone:BUFFER-COPY(bSource).
       hQuery:GET-NEXT().
    END.

    FINALLY:
    
        DELETE OBJECT bSource NO-ERROR.
        DELETE OBJECT bClone NO-ERROR.
    END FINALLY.
  END METHOD.  

  METHOD PROTECTED VOID CalcAdjustedValues(
    INPUT  dForwardInput         AS DECIMAL,
    INPUT  dBackwardInput        AS DECIMAL,
    INPUT  dForwardScale         AS DECIMAL,
    INPUT  dForwardShift         AS DECIMAL,
    INPUT  dForwardPreactivation AS DECIMAL,
    INPUT  dForwardOutput        AS DECIMAL,
    INPUT  dLearningRate         AS DECIMAL,
    OUTPUT dCorrectedScale       AS DECIMAL,
    OUTPUT dCorrectedShift       AS DECIMAL
):
    DEFINE VARIABLE dDelta          AS DECIMAL NO-UNDO.
    DEFINE VARIABLE dDeltaFactor    AS DECIMAL NO-UNDO.
    DEFINE VARIABLE dNewScale       AS DECIMAL NO-UNDO.
    DEFINE VARIABLE dNewShift       AS DECIMAL NO-UNDO.
    
    IF dForwardPreactivation < 0 THEN
    DO:
        ASSIGN dCorrectedScale = dForwardScale
               dCorrectedShift = dForwardShift.        
    END.
    ELSE DO:
        ASSIGN dDelta          = dBackwardInput - dForwardInput
               dDeltaFactor    = (dForwardInput + dDelta) / dForwardInput
               dNewScale       = dForwardScale * dDeltaFactor
               dNewShift       = dBackwardInput - dForwardInput - dNewScale
               dCorrectedScale = dForwardScale + (dNewScale - dForwardScale) * dLearningRate
               dCorrectedShift = dForwardShift + (dNewShift - dForwardShift) * dLearningRate.    
    END.

  END METHOD.
  
  
  
END CLASS.
