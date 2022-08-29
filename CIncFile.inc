
?MAXIFLEVEL	equ 31

INCFILE	struct 4
ifdef IMPL_INCFILE
pszIn			LPSTR ?	;pointer input stream
pszOut			LPSTR ?	;pointer output stream
pBuffer1		LPSTR ?	;buffer pointers in/out
pBuffer2		LPSTR ?	;buffer pointers in/out
dwBufSize		dd ?	;size of buffers
pDefs			LPSTR ?	;.DEF file content
pszFileName 	LPSTR ?	;file name
pszFullPath		LPSTR ?	;full path
pszLastToken	LPSTR ?	;
pszImpSpec		LPSTR ?
pszCallConv		LPSTR ?
pszEndMacro		LPSTR ?	;
pszStructName	LPSTR ?	;current struct/union/class name
dwBlockLevel	dd ?	;block level where pszEndMacro becomes active
dwQualifiers	dd ?	;
dwLine			dd ?	;current line
dwEnumValue		dd ?	;counter for enums
dwRecordNum		dd ?	;counter for records
;dwDefCallConv	dd ?	;default calling convention
dwErrors		dd ?	;errors occured in this file conversion
dwWarnings		dd ?	;warnings occured in this file conversion
dwBraces		dd ?	;count curled braces
pParent			dd ?	;parent INCFILE (if any)
filetime		FILETIME <>
bIfStack		db ?MAXIFLEVEL+1 dup (?)	;'if' stack
bIfLvl			db ?	;current 'if' level
bSkipPP			db ?	;>0=dont parse preprocessor lines in input stream
bNewLine		db ?	;last token was a PP_EOL
bContinuation	db ?	;preprocessor continuation line
bComment		db ?	;counter for "/*" and "*/" strings
bDefinedMac		db ?	;"defined" macro in output stream included
bAlignMac		db ?	;"@align" macro in output stream included
bUseLastToken	db ?
bC				db ?	;extern "C" occured
bIsClass		db ?	;inside a class definition
bIsInterface	db ?	;inside an interface definition
endif
INCFILE	ends


Create@IncFile		proto :LPSTR, :ptr INCFILE
Destroy@IncFile		proto :ptr INCFILE
Write@IncFile		proto :ptr INCFILE, :LPSTR
WriteDef@IncFile	proto :ptr INCFILE, :LPSTR
Parser@IncFile		proto :ptr INCFILE
Analyzer@IncFile	proto :ptr INCFILE
GetFileName@IncFile	proto :ptr INCFILE
GetFullPath@IncFile	proto :ptr INCFILE
;;GetLine@IncFile	proto :ptr INCFILE
GetParent@IncFile	proto :ptr INCFILE

