USING Progress.Lang.Object.
USING Progress.Json.ObjectModel.JsonObject.
USING Progress.Json.ObjectModel.JsonArray.
USING Progress.Lang.*.
USING AIModel.*.

CLASS AIModel.LLMNetwork:

  DEFINE PROTECTED PROPERTY OperatingMode AS CHARACTER 
      GET. 
      SET(iOperatingMode AS CHAR):
         IF LOOKUP(iOperatingMode,"TRAIN,PREDICT") = 0 THEN
            UNDO, THROW NEW AppError("Operating Mode must either be 'TRAIN' or 'PREDICT'",-1).
         THIS-OBJECT:OperatingMode = iOperatingMode.   
      END SET.

  DEFINE PRIVATE PROPERTY CallingProc AS HANDLE NO-UNDO GET. SET.    
    /* === Temp-table definition for layers === */
/*   DEFINE TEMP-TABLE ttLayers NO-UNDO             */
/*     FIELD LayerNum AS INTEGER                    */
/*     FIELD LayerObj AS CLASS Progress.Lang.Object */
/*     INDEX pr_u AS PRIMARY UNIQUE LayerNum.       */

/* === Method declarations === */

  {AIModel/LayerSharedDefs.i}
  
  DEFINE TEMP-TABLE ttLayer NO-UNDO
    FIELD layerNo AS INT
    FIELD layerCode AS CHAR
    FIELD oLayer  AS OBJECT.
    
  CONSTRUCTOR PUBLIC LLMNetwork (ihCallingProc AS HANDLE):
    THIS-OBJECT:CallingProc = ihCallingProc.
  
  END CONSTRUCTOR.

  METHOD PUBLIC VOID InitializeLayers(iOPeratingMode AS CHAR):
    DEFINE VARIABLE vr-LayerArchitecture AS CHARACTER     NO-UNDO.
    DEFINE VARIABLE i                    AS INTEGER       NO-UNDO.
    DEFINE VARIABLE vr-LayerCode         AS CHARACTER     NO-UNDO.
    DEFINE VARIABLE vr-ResLayerCount     AS INTEGER       NO-UNDO.
    DEFINE VARIABLE oResidualLayer       AS ResidualLayer NO-UNDO.
    DEFINE VARIABLE oLayer               AS Layer         NO-UNDO.
    DEFINE VARIABLE oLogitsLayer         AS LogitsLayer   NO-UNDO.
    DEFINE VARIABLE oOutputSoftmaxLayer  AS OutputSoftmaxLayer NO-UNDO.
    DEFINE VARIABLE oEmbeddingLayer      AS EmbeddingLayer NO-UNDO.
    
    THIS-OBJECT:OperatingMode = iOPeratingMode.
    ASSIGN vr-LayerArchitecture = {&LAYERARCHITECTURE}.
    DO i = 1 TO NUM-ENTRIES(vr-LayerArchitecture):
       ASSIGN vr-LayerCode = ENTRY(i,vr-LayerArchitecture).
       CREATE ttLayer.
       ASSIGN ttLayer.layerNo = i
              ttLayer.layerCode = vr-LayerCode.
       CASE vr-LayerCode:
           WHEN "EMB"  THEN ASSIGN oEmbeddingLayer = NEW EmbeddingLayer(ttLayer.layerNo,ttLayer.layerCode,THIS-OBJECT:callingProc)
                                   ttLayer.oLayer  = CAST(oEmbeddingLayer,OBJECT).
           WHEN "POS"  THEN ttLayer.oLayer = CAST(NEW PositionLayer(ttLayer.layerNo,ttLayer.layerCode,THIS-OBJECT:callingProc),OBJECT).
           WHEN "ATT"  THEN ttLayer.oLayer = CAST(NEW AttentionLayer(ttLayer.layerNo,ttLayer.layerCode,THIS-OBJECT:callingProc),OBJECT).
           WHEN "RES"  THEN DO:
                ASSIGN vr-ResLayerCount = THIS-OBJECT:getResLayerCount(OUTPUT oResidualLayer).
                IF vr-ResLayerCount MOD 2 > 0 THEN
                   ASSIGN ttLayer.oLayer = CAST(NEW ResidualLayer(ttLayer.layerNo,ttLayer.layerCode,THIS-OBJECT:callingProc),OBJECT).                   
                ELSE
                   ASSIGN ttLayer.oLayer = CAST(oResidualLayer,OBJECT).
//MESSAGE "vr-ResLayerCount" vr-ResLayerCount SKIP
//        "vr-ResLayerCount MOD 2" vr-ResLayerCount MOD 2 SKIP
//        "VALID-OBJECT(ttLayer.oLayer)" VALID-OBJECT(ttLayer.oLayer) SKIP
//    VIEW-AS ALERT-BOX INFORMATION BUTTONS OK.
                   
           END.
           WHEN "NORM" THEN ttLayer.oLayer = CAST(NEW NormalizationLayer(ttLayer.layerNo,ttLayer.layerCode,THIS-OBJECT:callingProc),OBJECT).
           WHEN "FF"   THEN ttLayer.oLayer = CAST(NEW FeedForwardLayer(ttLayer.layerNo,ttLayer.layerCode,THIS-OBJECT:callingProc),OBJECT).
           WHEN "LOG"  THEN ASSIGN oLogitsLayer = NEW LogitsLayer(ttLayer.layerNo,ttLayer.layerCode,THIS-OBJECT:callingProc) 
                                   ttLayer.oLayer = CAST(oLogitsLayer,OBJECT).
           WHEN "OUT"  THEN DO:
                 ASSIGN oOutputSoftmaxLayer = NEW OutputSoftmaxLayer(ttLayer.layerNo,ttLayer.layerCode,THIS-OBJECT:callingProc)
                        ttLayer.oLayer      = CAST(oOutputSoftmaxLayer,OBJECT).  
                 oOutputSoftmaxLayer:oLogitsLayer = oLogitsLayer.    
                 oOutputSoftmaxLayer:oEmbeddingLayer = oEmbeddingLayer.
           END.
           OTHERWISE DO:
               UNDO, THROW NEW AppError(SUBST("Layer Code '&1' is not valid",vr-LayerCode),-1). 
           END.
       END CASE.
    END.
    FIND FIRST ttLayer NO-ERROR.
    IF AVAIL ttLayer THEN
    DO:
        oLayer = CAST(ttLayer.oLayer,Layer).
        oLayer:ResetState().
    END.
  END METHOD.
  
  METHOD PRIVATE INTEGER getResLayerCount (OUTPUT oLastResLayer AS ResidualLayer):
    DEF VAR iResLayerCount AS INT NO-UNDO.
    DEF BUFFER ttLayer FOR ttLayer.
    FOR EACH ttLayer 
        WHERE ttLayer.layerCode = "RES"
        BY ttLayer.layerNo:
        ASSIGN iResLayerCount = iResLayerCount + 1
               oLastResLayer  = CAST(ttLayer.oLayer,ResidualLayer)
                                WHEN VALID-OBJECT(ttLayer.oLayer).
    END.  
//MESSAGE "VALID-OBJECT(oLastResLayer)" VALID-OBJECT(oLastResLayer) SKIP
//    VIEW-AS ALERT-BOX INFORMATION BUTTONS OK.
    RETURN iResLayerCount.
  END METHOD.


  METHOD PUBLIC VOID Train():
  END METHOD.

  METHOD PUBLIC VOID forward(INPUT lcInput AS LONGCHAR):
    DEFINE VARIABLE oLayer            AS Layer      NO-UNDO.
    DEFINE VARIABLE lcForwardResult   AS LONGCHAR   NO-UNDO.
    /* This base method does nothing. Override in subclasses. */
    //EMPTY TEMP-TABLE ttLogits.
    FIX-CODEPAGE(lcForwardResult) = "UTF-8".  
    lcForwardResult = lcInput.
    FOR EACH ttLayer BY ttLayer.layerNo:
        oLayer = CAST(ttLayer.oLayer,Layer).
        lcForwardResult = oLayer:forward(lcForwardResult).
IF lcForwardResult = ? THEN
DO:
   MESSAGE "ttLayer.layerNo" ttLayer.layerNo SKIP
           "ttLayer.layerCode" ttLayer.layerCode SKIP
           "lcForwardResult" STRING(lcForwardResult) 
       VIEW-AS ALERT-BOX INFORMATION BUTTONS OK.
END.  
THIS-OBJECT:checkResult(ttLayer.layerCode,"forward", lcForwardResult).

    END.    
    //RETURN lcForwardResult.
  END METHOD.

  METHOD PUBLIC LONGCHAR backward(INPUT lcGradient AS LONGCHAR):
    DEFINE VARIABLE oLayer AS Layer   NO-UNDO.
    
    FOR EACH ttLayer BY ttLayer.layerNo DESC:
      oLayer = CAST(ttLayer.oLayer,Layer).
      lcGradient = oLayer:backward(lcGradient).
      
THIS-OBJECT:checkResult(ttLayer.layerCode,"backward", lcGradient).      
    END.
    RETURN lcGradient.
  END METHOD.

  METHOD PUBLIC LONGCHAR getPredictions(INPUT cTargetTokenIds AS CHARACTER):
      DEFINE VARIABLE oOutputSoftmaxLayer AS OutputSoftmaxLayer   NO-UNDO.
      FIND LAST ttLayer WHERE ttLayer.LayerCode = "OUT" NO-ERROR.
      IF NOT AVAIL ttLayer THEN
         UNDO, THROW NEW PROGRESS.LANG.APPERROR("OutputSoftmaxLayer layer not found",-1).
      ASSIGN oOutputSoftmaxLayer = CAST(ttLayer.oLayer,OutputSoftmaxLayer).
      RETURN oOutputSoftmaxLayer:getPredictions(cTargetTokenIds).
  END METHOD.  
    
  METHOD PUBLIC LONGCHAR PrepareForBackwardPass(INPUT cTargetTokenIds AS CHARACTER):
      DEFINE VARIABLE oOutputSoftmaxLayer AS OutputSoftmaxLayer   NO-UNDO.
      FIND LAST ttLayer WHERE ttLayer.LayerCode = "OUT" NO-ERROR.
      IF NOT AVAIL ttLayer THEN
         UNDO, THROW NEW PROGRESS.LANG.APPERROR("OutputSoftmaxLayer layer not found",-1).
      ASSIGN oOutputSoftmaxLayer = CAST(ttLayer.oLayer,OutputSoftmaxLayer).
      RETURN oOutputSoftmaxLayer:PrepareForBackwardPass(cTargetTokenIds).
  END METHOD.  
  /* Method: serialize
     Abstract method to be implemented by subclasses to return layer configuration/state. */
  METHOD PUBLIC JsonObject serialize():
    DEFINE VARIABLE oJsonTT           AS JsonObject NO-UNDO.
    DEFINE VARIABLE oJsonBase         AS JsonObject NO-UNDO.
    DEFINE VARIABLE oJsonSerialized AS JsonObject NO-UNDO.
    DEFINE VARIABLE oLayer          AS layer      NO-UNDO.
    ASSIGN oJsonSerialized = NEW JsonObject().
    oJsonSerialized:ADD("Layers",NEW JsonArray()).
    FOR EACH ttLayer BY ttLayer.layerNo:
        oLayer = CAST(ttLayer.oLayer,Layer).
        ASSIGN oJsonTT = oLayer:serialize().
               oJsonBase = NEW JsonObject().
        //oJsonBase:ADD(ttLayer.LayerCode,NEW JsonObject()).
        oJsonBase:ADD(ttLayer.LayerCode,oJsonTT).
        oJsonSerialized:GetJsonArray('Layers'):ADD(oJsonBase).
    END.
    RETURN oJsonSerialized. /* Placeholder to ensure valid return type */
  END METHOD.

  METHOD PUBLIC JsonObject serialize(icFileName AS CHAR):
     DEFINE VARIABLE oJsonSerialized AS JsonObject NO-UNDO.
     oJsonSerialized = THIS-OBJECT:serialize().
     oJsonSerialized:writeFile(icFileName,TRUE).
  END METHOD.
  
  METHOD PUBLIC VOID Deserialize(INPUT jsonData AS CLASS JsonObject):
  
  END METHOD.

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

  METHOD PUBLIC VOID instantiateTracer (iiLayerNo AS INT):
      DEFINE VARIABLE oLayer AS Layer   NO-UNDO.
      FIND FIRST ttLayer WHERE ttLayer.LayerNo = iiLayerNo NO-ERROR.
      IF AVAIL ttLayer THEN
      DO:
          oLayer = CAST(ttLayer.oLayer,Layer).
          oLayer:instantiateTracer().
      END.
  END METHOD.
  
  
  METHOD PRIVATE VOID checkResult (INPUT icLayerCode AS CHAR,
                                   INPUT icDirection AS CHAR,
                                   INPUT icPayLoad AS LONGCHAR):
  
        EMPTY TEMP-TABLE ttContextEmbedding.
        TEMP-TABLE ttContextEmbedding:READ-JSON("LONGCHAR",icPayLoad,"empty") NO-ERROR.
        IF ERROR-STATUS:ERROR THEN
        DO:
            MESSAGE "ERROR-STATUS:GET-MESSAGE(1)" ERROR-STATUS:GET-MESSAGE(1) SKIP
                VIEW-AS ALERT-BOX INFORMATION BUTTONS OK.
        END.
        FOR EACH ttContextEmbedding
            BREAK BY ttContextEmbedding.posNo BY ttContextEmbedding.tokenId:
            IF NOT (FIRST-OF(ttContextEmbedding.tokenId) AND LAST-OF(ttContextEmbedding.tokenId))  THEN
            DO:
                MESSAGE "duplictate" SKIP
                        "icLayerCode" icLayerCode SKIP
                        "icDirection" icDirection SKIP
                    VIEW-AS ALERT-BOX INFORMATION BUTTONS OK.
                QUIT.    
            END.
        END.
  END METHOD.
        
END CLASS.
