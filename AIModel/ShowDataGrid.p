/*............................................................................
 file-name: ShowDataGrid.p
 Purpose  : Show data of the matrix table at the layer level as it is being
            updated
            
 Notes    : This program is being run persistently. It receives as input 
            the buffer handle to the table for which it is going to
            display a dynamic browse
            If the reference table contains multiple array fields
            then a dynamic browse will be instantiated for every browse
.............................................................................*/


DEFINE INPUT PARAMETER iiLayerNo     AS INTEGER   NO-UNDO.
DEFINE INPUT PARAMETER icLayerCode   AS CHARACTER NO-UNDO.
DEFINE INPUT PARAMETER ihBuffer      AS HANDLE    NO-UNDO.

DEFINE VARIABLE        iLayerNo      AS INTEGER   NO-UNDO.
DEFINE VARIABLE        cLayerCode    AS CHARACTER NO-UNDO.
DEFINE VARIABLE        hBuffer       AS HANDLE    NO-UNDO.
DEFINE VARIABLE        hLocalBuffer  AS HANDLE    NO-UNDO.
DEFINE VARIABLE        hQuery        AS HANDLE    NO-UNDO.
DEFINE VARIABLE        hWin          AS HANDLE    NO-UNDO.
DEFINE VARIABLE        hFrame        AS HANDLE    NO-UNDO.
DEFINE VARIABLE        hBrowse       AS HANDLE    NO-UNDO. 
DEFINE VARIABLE        iCnt          AS INTEGER   NO-UNDO.
DEFINE VARIABLE        iWindowWidth  AS INTEGER   NO-UNDO.
DEFINE VARIABLE        iWindowHeight AS INTEGER   NO-UNDO.


FUNCTION fn_GetExtentField RETURN HANDLE(ihBuffer AS HANDLE) FORWARD.

ASSIGN iLayerNo   = iiLayerNo
       cLayerCode = icLayerCode
       hBuffer    = ihBuffer.

CREATE BUFFER hLocalBuffer FOR TABLE hBuffer.       
  
CREATE WINDOW hWin ASSIGN
  WIDTH-PIXELS  = 800
  HEIGHT-PIXELS = 400
  RESIZE        = TRUE
  TITLE         = SUBST("Datagrid for layer '&1', type '&2'",iLayerNo,icLayerCode)
  .
  
ASSIGN hWin:VISIBLE       = TRUE
       hWin:SENSITIVE     = TRUE.

ASSIGN iWindowWidth  = hWin:WIDTH-PIXELS  
       iWindowHeight = hWin:HEIGHT-PIXELS.
  
CREATE FRAME hFrame
   ASSIGN ROW = 1
          COL = 1
          //WIDTH-CHARS = 120
          //HEIGHT-CHARS = 40
          WIDTH-PIXELS = hWin:WIDTH-PIXELS - 5 //600
          HEIGHT-PIXELS = hWin:HEIGHT-PIXELS - 5 // 320
          TITLE = hWin:TITLE
          BGCOLOR = 8
          PARENT = hWin
          VISIBLE = TRUE
          .
CREATE QUERY hQuery.
hQuery:ADD-BUFFER(hLocalBuffer).
hQuery:QUERY-PREPARE(SUBST("FOR EACH &1",hLocalBuffer:NAME)).
hQuery:QUERY-OPEN().

CREATE BROWSE hBrowse
  ASSIGN 
    TITLE     = "Matrix"
    FRAME     = hFrame
    QUERY     = hQuery
    X         = 1
    Y         = 1
    WIDTH-PIXELS = hFrame:WIDTH-PIXELS - 10 //590
    HEIGHT-PIXELS = hFrame:HEIGHT-PIXELS - 30 //290
    VISIBLE   = YES
    SENSITIVE = TRUE
    //READ-ONLY = NO
    .
RUN addBrowseColumns (hBrowse,hLocalBuffer).

hBrowse:REFRESH().   
   
ON 'window-close':U OF hWin 
DO:
    APPLY 'close' TO THIS-PROCEDURE.    
    RETURN.
END.
ON 'window-resized':U OF hWin 
DO:
    RUN windowResize.
    RETURN.
END.
       
SUBSCRIBE PROCEDURE THIS-PROCEDURE TO "browseRefresh" ANYWHERE.

//WAIT-FOR 'CLOSE' OF THIS-PROCEDURE.
ON 'close':U OF THIS-PROCEDURE
DO:
    RUN destroy. 
    RETURN.
END.
 

PROCEDURE addBrowseColumns:
   DEFINE INPUT  PARAMETER ihBrowse      AS HANDLE      NO-UNDO.
   DEFINE INPUT  PARAMETER ihBuffer      AS HANDLE      NO-UNDO.
   
   DEFINE VARIABLE iCnt             AS INTEGER     NO-UNDO.
   DEFINE VARIABLE hExtentField     AS HANDLE      NO-UNDO.
   DEFINE VARIABLE hColumn          AS HANDLE      NO-UNDO.
   ASSIGN hColumn = ihBrowse:ADD-LIKE-COLUMN(SUBST("&1.&2",hLocalBuffer:NAME,hLocalBuffer:BUFFER-FIELD(1):NAME))
          hColumn:LABEL = "Row"          
          hColumn:LABEL-FGCOLOR = 12
          hColumn:LABEL-BGCOLOR = 9.
   ASSIGN hExtentField = fn_GetExtentField(ihBuffer).
   DO iCnt = 1 TO hExtentField:EXTENT:
      hColumn = ihBrowse:ADD-LIKE-COLUMN(SUBST("&1.&2[&3]",
                                           hLocalBuffer:NAME,
                                           hExtentField:NAME,
                                           iCnt)).
      ASSIGN hColumn:LABEL = STRING(iCnt).
      ASSIGN hColumn = ihBrowse:GET-BROWSE-COLUMN(iCnt + 1) 
             hColumn:COLUMN-BGCOLOR = 8
             hColumn:COLUMN-FGCOLOR = 1.
   END.
END PROCEDURE.

PROCEDURE browseRefresh:
   DEFINE INPUT  PARAMETER iiLayerNo AS INTEGER     NO-UNDO.
    
   IF iLayerNo = iiLayerNo THEN
   DO:
      hQuery:QUERY-CLOSE().
      hQuery:QUERY-OPEN().
      hBrowse:REFRESH().
   END.
END PROCEDURE.

PROCEDURE destroy:
    DELETE OBJECT hLocalBuffer NO-ERROR.
    DELETE OBJECT hWin NO-ERROR.
    DELETE OBJECT hFrame NO-ERROR.
    DELETE OBJECT hQuery NO-ERROR.
    DELETE OBJECT hBrowse NO-ERROR.
END PROCEDURE.

PROCEDURE windowResize:
    IF hWin:WIDTH-PIXELS > iWindowWidth AND 
       hWin:HEIGHT-PIXELS > iWindowHeight THEN
    DO:
       ASSIGN hFrame:WIDTH-PIXELS = hWin:WIDTH-PIXELS - 5
              hFrame:HEIGHT-PIXELS = hWin:HEIGHT-PIXELS - 5
              hBrowse:WIDTH-PIXELS = hFrame:WIDTH-PIXELS - 10
              hBrowse:HEIGHT-PIXELS = hFrame:HEIGHT-PIXELS - 30
              .
    END.

END PROCEDURE.
FUNCTION fn_GetExtentField RETURN HANDLE(ihBuffer AS HANDLE):
   DEFINE VARIABLE hBufFld AS HANDLE      NO-UNDO.
   DEFINE VARIABLE i       AS INTEGER     NO-UNDO.  
   
   
   DO i = 1 TO hLocalBuffer:NUM-FIELDS:
      IF hLocalBuffer:BUFFER-FIELD(i):EXTENT > 1 THEN
      DO:
          hBufFld = hLocalBuffer:BUFFER-FIELD(i).
          LEAVE.
      END.
   END.
   RETURN hBufFld.
END FUNCTION.
