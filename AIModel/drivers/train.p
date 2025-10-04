/*************************  **********************************************************************************
   file-name: train.p
***********************************************************************************************************/
USING Progress.Lang.Object.
USING Progress.Json.ObjectModel.JsonObject.
USING Progress.Lang.*.
USING AIModel.*.

DEFINE VARIABLE vr-SampleFile AS CHARACTER   NO-UNDO.
DEFINE VARIABLE oLayer AS layer NO-UNDO.
DEFINE VARIABLE oLLMNetwork AS LLMNetwork   NO-UNDO.
DEFINE VARIABLE lcExamples AS LONGCHAR   NO-UNDO.   
DEFINE VARIABLE i AS INTEGER     NO-UNDO.
DEFINE VARIABLE j AS INTEGER     NO-UNDO.
DEFINE VARIABLE cExample     AS CHARACTER   NO-UNDO FORMAT "x(20)".
DEFINE VARIABLE cPredictions AS CHARACTER   NO-UNDO FORMAT "x(20)".
DEFINE VARIABLE lcResult AS LONGCHAR   NO-UNDO.
DEFINE VARIABLE cTargetTokenIds AS CHARACTER   NO-UNDO.
DEFINE VARIABLE iIdx AS INTEGER     NO-UNDO.
DEFINE VARIABLE iNoOfEpochs AS INTEGER     NO-UNDO INIT 30.

FIX-CODEPAGE(lcExamples) = "UTF-8".
FIX-CODEPAGE(lcResult) = "UTF-8".

ASSIGN vr-SampleFile = "C:\OpenEdge\WRK\AIModel\examples\SampleSet.txt".

COPY-LOB FILE vr-SampleFile TO lcExamples. 

oLLMNetwork = NEW LLMNetwork(THIS-PROCEDURE).
oLLMNetwork:InitializeLayers("TRAIN").
oLLMNetwork:initializeWeights().
oLLMNetwork:instantiateTracer(1).
PAUSE 0 BEFORE-HIDE.
DO j = 1 TO iNoOfEpochs WITH DOWN FRAME a:
    DO i = 1 TO NUM-ENTRIES(lcExamples,"~n"):
       ASSIGN cExample = REPLACE(ENTRY(i,lcExamples,"~n"),"~r","").
       //MESSAGE STRING(cExample).
       oLLMNetwork:FORWARD(cExample).
       IF LENGTH(cExample) < 3  OR cExample = ? THEN NEXT.
       
//MESSAGE  cExample
//    VIEW-AS ALERT-BOX INFORMATION BUTTONS OK.
       ASSIGN  iIdx = INDEX(cExample,"=").
       IF iIdx > 0  THEN
          cTargetTokenIds = SUBSTR(cExample,iIdx + 1).
          
       ASSIGN cPredictions = oLLMNetwork:getPredictions(cTargetTokenIds)   
              lcResult     = oLLMNetwork:PrepareForBackwardPass(cTargetTokenIds).
       DISPLAY cExample cPredictions WITH FRAME a.
       DOWN WITH FRAME a.     
       PROCESS EVENTS.
       oLLMNetwork:BACKWARD(lcResult).
       
       //lcResult = oLayer:BACKWARD(lcResult).
    END.
END.    
oLLMNetwork:serialize("C:\temp\faj.json").
