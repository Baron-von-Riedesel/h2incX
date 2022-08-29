
;--- implements INCFILE class

	.386
	.model flat, stdcall
	option casemap:none
	option proc:private

	.nolist
	.nocref
	include winbase.inc
	include stdlib.inc
	include stdio.inc
	include macros.inc
	.list
	.cref

?IFISSTRUCT		equ 1		;handle "interface" as "struct"
?MAXSTRUCTNAME	equ 128
?MAXITEMS		equ 10000h	;max. items in structure/macro list
?ADDTERMNULL	equ 0		;add ",0" to string declarations
?ADD50PERCENT	equ 0		;1=buffer size 50% larger than file size
							;0=buffer size 100% larger than file size
?USELOCALALLOC	equ 0		;1=use LocalAlloc, 0=use _malloc()


	include h2incX.inc
IMPL_INCFILE equ 1        
	include CIncFile.inc
	include CList.inc

_this	equ <ebx>

;--- equates for easy member access

m_pszIn			equ <[_this].INCFILE.pszIn>
m_pszOut		equ <[_this].INCFILE.pszOut>
m_pBuffer1		equ <[_this].INCFILE.pBuffer1>
m_pBuffer2		equ <[_this].INCFILE.pBuffer2>
m_dwBufSize		equ <[_this].INCFILE.dwBufSize>
m_pDefs     	equ <[_this].INCFILE.pDefs>
m_pszFileName	equ <[_this].INCFILE.pszFileName>
m_pszFullPath	equ <[_this].INCFILE.pszFullPath>
m_pszLastToken	equ <[_this].INCFILE.pszLastToken>
m_pszImpSpec	equ <[_this].INCFILE.pszImpSpec>
m_pszCallConv	equ <[_this].INCFILE.pszCallConv>
m_pszEndMacro	equ <[_this].INCFILE.pszEndMacro>
m_pszStructName	equ <[_this].INCFILE.pszStructName>
m_dwBlockLevel	equ <[_this].INCFILE.dwBlockLevel>
m_dwQualifiers	equ <[_this].INCFILE.dwQualifiers>
m_dwLine		equ <[_this].INCFILE.dwLine>
m_dwEnumValue	equ <[_this].INCFILE.dwEnumValue>
m_dwRecordNum	equ <[_this].INCFILE.dwRecordNum>
;;m_dwDefCallConv equ <[_this].INCFILE.dwDefCallConv>
m_dwErrors		equ <[_this].INCFILE.dwErrors>
m_dwWarnings	equ <[_this].INCFILE.dwWarnings>
m_dwBraces		equ <[_this].INCFILE.dwBraces>
m_pParent		equ <[_this].INCFILE.pParent>
m_filetime		equ <[_this].INCFILE.filetime>
m_bIfStack		equ <[_this].INCFILE.bIfStack>
m_bIfLvl		equ <[_this].INCFILE.bIfLvl>
m_bSkipPP		equ <[_this].INCFILE.bSkipPP>
m_bNewLine		equ <[_this].INCFILE.bNewLine>
m_bContinuation	equ <[_this].INCFILE.bContinuation>
m_bComment		equ <[_this].INCFILE.bComment>
m_bDefinedMac	equ	<[_this].INCFILE.bDefinedMac>
m_bAlignMac		equ	<[_this].INCFILE.bAlignMac>
m_bUseLastToken	equ	<[_this].INCFILE.bUseLastToken>
m_bC			equ	<[_this].INCFILE.bC>
m_bIsClass		equ	<[_this].INCFILE.bIsClass>
m_bIsInterface	equ <[_this].INCFILE.bIsInterface>

GetNextToken	proto
GetNextTokenPP	proto
getblock		proto pszName:LPSTR, dwMode:DWORD, pszParent:LPSTR
MacroInvocation proto :LPSTR, :ptr NAMEITEM, :DWORD
ProcessFile		proto :LPSTR, :ptr INCFILE
ParseTypedefFunction	proto pszName:LPSTR, :DWORD, pszParent:LPSTR
ParseTypedefFunctionPtr proto pszParent:LPSTR
TranslateName	proto :LPSTR, :LPSTR

;--- types for getblock()

DT_STANDARD equ 0	;struct/union
DT_EXTERN	equ 1	;extern
DT_ENUM		equ 2	;enum

;--- parser output ctrl codes

PP_MACRO	equ 0E0h	;is a macro
PP_EOL		equ 0E1h	;end of line
PP_COMMENT	equ 0E2h	;comment token
PP_IGNORE	equ 0E3h	;ignore token
PP_WEAKEOL	equ 0E4h	;'\' at the end of preprocessor lines

;--- flag values in [Known Macros]

MF_0001			equ 001h	;reserved
MF_SKIPBRACES	equ 002h	;skip braces in macro call
MF_COPYLINE		equ 004h	;assume rest of line belongs to macro call
MF_PARAMS		equ 008h	;assume method parameters coming after macro
MF_???			equ 010h
MF_ENDMACRO		equ 020h	;end next block with a ???_END macro call
MF_STRUCTBEG	equ 040h	;macro begins a struct/union (MIDL_INTERFACE)
MF_INTERFACEBEG equ 080h	;add an "??Interface equ <xxx>" line
MF_INTERFACEEND equ 100h	;add an "??Interface equ <>" line

INPSTAT	struct
pszIn		dd ?
dwLine		dd ?
bIfStack	db ?MAXIFLEVEL dup (?)
bIfLvl		db ?
bNewLine	db ?
INPSTAT	ends

;--- macros

Create@Stacklist macro
	push 0
	mov eax,esp
	endm

Destroy@Stacklist macro x
	endm

Add@Stacklist macro x, y
	push y
	mov ecx,x
	inc dword ptr [ecx]
	endm

GetNumItems@Stacklist macro x
	mov eax, x
	mov eax, [eax]
	endm

GetItem@Stacklist macro x, y
	mov eax, x
	mov ecx, y
	shl ecx, 2
	sub eax, ecx
	mov eax,[eax-4]
	endm

	.data

;--- preprocessor command tab
;--- commands not listed here will be commented out

PPCMD	struct
pszCmd		dd ?
pfnHandler	dd ?
PPCMD	ends

ppcmds label PPCMD
	PPCMD <CStr("define"), offset IsDefine>
	PPCMD <CStr("include"), offset IsInclude>
	PPCMD <CStr("error"), offset IsError>
	PPCMD <CStr("pragma"), offset IsPragma>
	PPCMD <CStr("if"), offset IsIf>
	PPCMD <CStr("elif"), offset IsElIf>
	PPCMD <CStr("else"), offset IsElse>
	PPCMD <CStr("endif"), offset IsEndif>
	PPCMD <CStr("ifdef"), offset IsIfdef>
	PPCMD <CStr("ifndef"), offset IsIfndef>
	dd 0

ppcmdsnp label PPCMD
	PPCMD <CStr("if"), offset IsIfNP>
	PPCMD <CStr("elif"), offset IsElIfNP>
	PPCMD <CStr("else"), offset IsElseNP>
	PPCMD <CStr("endif"), offset IsEndifNP>
	PPCMD <CStr("ifdef"), offset IsIfNP>
	PPCMD <CStr("ifndef"), offset IsIfNP>
	dd 0

;--- operator conversion for #if/#elif expressions

OPCONV struct
wOp		db 2 dup (?)
pszSubst LPSTR ?
OPCONV ends

g_szOpConvTab label dword
	OPCONV <"==", CStr(" eq ")>
	OPCONV <"!=", CStr(" ne ")>
if 0;__JWASM__
	OPCONV <<3Eh,'='>, CStr(" ge ")>
	OPCONV <<3Ch,'='>, CStr(" le ")>
	OPCONV <3Eh,  CStr(" gt ")>
	OPCONV <3Ch,  CStr(" lt ")>
else
	OPCONV <">=", CStr(" ge ")>
	OPCONV <"<=", CStr(" le ")>
	OPCONV <">",  CStr(" gt ")>
	OPCONV <"<",  CStr(" lt ")>
endif   
	OPCONV <"&&", CStr(" AND ")>
	OPCONV <"||", CStr(" OR ")>
	OPCONV <"!",  CStr(" 0 eq ")>
sizeOpConvTab equ ($ - offset g_szOpConvTab) / sizeof OPCONV		

	.const

szMac_defined label byte
	db "ifndef defined",cr,lf
	db "defined macro x",cr,lf
	db "ifdef x",cr,lf
	db "  exitm <1>",cr,lf
	db "else",cr,lf
	db "  exitm <0>",cr,lf
	db "endif",cr,lf
	db "endm",cr,lf
	db "endif",cr,lf
	db 0
szMac_align label byte
	db "ifndef @align",cr,lf
	db "@align equ <>",cr,lf
	db "endif",cr,lf
	db 0

;--- delimiters known by parser

bDelim	db ",;:()[]{}|*<>!~-+=/&#"

;--- 2-byte opcodes known by parser

w2CharOps dw ">>","<<","&&","||",">=","<=","==","!=","->","::","##"

	.DATA?

g_szComment	db 1024 dup (?)
g_szTemp	db 128	dup (?)

	.code

SaveInputStatus proc pStatus:ptr INPSTAT
	pushad
	mov esi, pStatus
	mov eax,m_pszIn
	mov ecx,m_dwLine
	mov dl,m_bNewLine
	mov dh,m_bIfLvl
	mov [esi].INPSTAT.pszIn, eax
	mov [esi].INPSTAT.dwLine, ecx
	mov [esi].INPSTAT.bNewLine, dl
	mov [esi].INPSTAT.bIfLvl, dh
	lea edi, [esi].INPSTAT.bIfStack
	lea esi, m_bIfStack
	mov ecx, ?MAXIFLEVEL/4
	rep movsd
	popad
	ret
SaveInputStatus endp

RestoreInputStatus proc pStatus:ptr INPSTAT
	pushad
	mov esi, pStatus
	mov eax,[esi].INPSTAT.pszIn
	mov ecx, [esi].INPSTAT.dwLine
	mov dl,[esi].INPSTAT.bNewLine
	mov dh,[esi].INPSTAT.bIfLvl
	mov m_pszIn, eax
	mov m_dwLine, ecx
	mov m_bNewLine, dl
	mov m_bIfLvl, dh
	lea edi, m_bIfStack
	lea esi, [esi].INPSTAT.bIfStack
	mov ecx, ?MAXIFLEVEL/4
	rep movsd
	popad
	ret
RestoreInputStatus endp

;--- add an item to a list

InsertItem proc pList:ptr LIST, pszName:LPSTR, dwValue:DWORD
	invoke AddString, pszName, dwValue
	.if (eax)
		invoke AddItem@List, pList, eax
		.if (!eax)
			invoke printf, CStr("%s, %u: out of symbol space",lf),
				m_pszFileName, m_dwLine
			inc m_dwErrors
			mov g_bTerminate, TRUE
			xor eax, eax
		.endif
	.endif
	ret
InsertItem endp

;--- add a prototype to a list

InsertDefItem proc pszFuncName:LPSTR, dwParmBytes:DWORD

local	szProto[MAX_PATH]:BYTE

	.if (m_dwQualifiers & FQ_STDCALL)
		invoke sprintf, addr szProto, CStr("_%s@%u"), pszFuncName, dwParmBytes
	.elseif (m_dwQualifiers & FQ_CDECL)
		invoke sprintf, addr szProto, CStr("_%s"), pszFuncName
	.else
		invoke sprintf, addr szProto, CStr("%s"), pszFuncName
	.endif
	invoke AddString, addr szProto, 0
	.if (eax)
		invoke AddItem@List, m_pDefs, eax
		.if (!eax)
			invoke printf, CStr("%s, %u: out of space",lf),
				m_pszFileName, m_dwLine
			inc m_dwErrors
			mov g_bTerminate, TRUE
			xor eax, eax
		.endif
	.endif
	ret
InsertDefItem endp

;--- write a string to output stream

write proc uses esi edi pszText:LPSTR
	mov esi, pszText
	mov edi, m_pszOut
@@:
	lodsb
	stosb
	and al,al
	jnz @B
	dec edi
	mov m_pszOut, edi
	ret
write endp

IsNewLine proc
	mov ecx, m_pszOut
	xor eax, eax
	mov al,byte ptr [ecx-1]
	cmp al,lf
	sete al
	ret
IsNewLine endp

xprintf proc c pszFormat:LPSTR, args:VARARG
	lea ecx, args
	invoke vsprintf, m_pszOut, pszFormat, ecx
	add m_pszOut, eax
	ret
xprintf endp


IsDelim proc
	pushad
	mov edi, offset bDelim
	mov ecx, sizeof bDelim
	repnz scasb
	popad
	ret 
IsDelim endp

IsTwoCharOp proc
	pushad
	xchg al,ah
	mov edi, offset w2CharOps
	mov ecx, (sizeof w2CharOps)/2
	repnz scasw
	popad
	ret
IsTwoCharOp endp

;--- translate tokens like "__export" or "__stdcall"

TranslateToken proc uses esi pszType:ptr BYTE

	mov esi, g_ppConvertTokens
	.while (dword ptr [esi])
		lodsd
		invoke _strcmp, pszType, eax
		.if (!eax)
			lodsd
			ret
		.endif
		lodsd
	.endw
	mov eax, pszType
	ret
TranslateToken endp

GetAlignment proc uses esi pszStructure:ptr BYTE
	mov esi, g_ppAlignments
	.while (dword ptr [esi])
		lodsd
		invoke _strcmp, pszStructure, eax
		.if (!eax)
			lodsd
			ret
		.endif
		add esi, 4
	.endw
	xor eax, eax
	ret
GetAlignment endp

;--- get type sizes (for structures used as parameters)

GetTypeSize proc uses esi pszType:ptr BYTE
	mov esi, g_ppTypeSize
	.while (dword ptr [esi])
		lodsd
		invoke _strcmp, pszType, eax
		.if (!eax)
			lodsd
			ret
		.endif
		add esi, 4
	.endw
	mov eax, 4
	ret
GetTypeSize endp

;--- convert type qualifiers

ConvertTypeQualifier proc uses esi pszType:ptr BYTE

	mov esi, g_ppTypeAttrConv
	.while (dword ptr [esi])
		lodsd
		.if (byte ptr [eax] == '*')
			inc eax
			invoke lstrcmpi, pszType, eax
		.else
			invoke _strcmp, pszType, eax
		.endif
		.if (!eax)
			lodsd
			ret
		.endif
		lodsd
	.endw
	mov eax, pszType
	ret
ConvertTypeQualifier endp

;--- translate a type.
;--- 1. scan "type conversion 1" table
;--- 2. if bMode == 0, scan "type conversion 2"
;---    if bMode != 0, scan "type conversion 3"
;--- if nothing found, return pszType or "DWORD"

TranslateType proc uses esi pszType:ptr BYTE, bMode:DWORD

	mov esi, g_ppConvertTypes1
	.while (dword ptr [esi])
		lodsd
		invoke _strcmp, pszType, eax
		.if (!eax)
			lodsd
			ret
		.endif
		lodsd
	.endw
	.if (bMode)
		mov esi, g_ppConvertTypes3
	.else
		mov esi, g_ppConvertTypes2
	.endif
	.while (dword ptr [esi])
		lodsd
		invoke _strcmp, pszType, eax
		.if (!eax)
			lodsd
			ret
		.endif
		lodsd
	.endw
	.if (bMode)
		mov eax, CStr("DWORD")
	.else
		mov eax, pszType
	.endif
	ret

TranslateType endp

;--- check if a token is a simple type
;--- used by SkipCasts() 

IsSimpleType proc uses esi pszType:ptr byte

	mov esi, g_ppSimpleTypes
	.while (dword ptr [esi])
		lodsd
		invoke _strcmp, pszType, eax
		.if (!eax)
			mov eax, 1
			ret
		.endif
	.endw
	xor eax, eax
	ret

IsSimpleType endp

;--- check if a token is a structure

IsStructure proc pszType:LPSTR

if 0
	mov esi, g_KnownStructures.pItems
	.while (dword ptr [esi])
		lodsd
		invoke _strcmp, pszType, eax
		.if (!eax)
			inc eax
			ret
		.endif
	.endw
endif
	invoke _bsearch, addr pszType, g_KnownStructures.pItems,
		g_KnownStructures.numItems, 4, cmpproc
	.if (!eax)
		invoke FindItem@List, g_pStructures, pszType
	.endif
	ret

IsStructure endp


WriteComment proc
	xor eax, eax
	.if (g_bIncludeComments && (byte ptr g_szComment+1))
		invoke write, addr g_szComment
		mov g_szComment+1,0
		mov eax, 1
	.endif
	ret
WriteComment endp

AddComment proc pszToken:LPSTR
	mov edx, pszToken
	inc edx
	invoke lstrcpy, addr g_szComment+1, edx
	mov g_szComment, ';'
	ret
AddComment endp

;--- get next token (for preprocessor lines)

GetNextTokenPP proc uses edi

	mov edi, m_pszIn
nextline:
	mov ecx,-1
	mov al,0
	repnz scasb
	not ecx
	dec ecx
	xor eax, eax
	mov m_bNewLine, FALSE
	.if (ecx)
		mov eax, edi
		xchg eax, m_pszIn
		.if (word ptr [eax] == PP_EOL)
			inc m_dwLine
			mov m_bNewLine, TRUE
			xor eax,eax
		.elseif (word ptr [eax] == PP_WEAKEOL)
			inc m_dwLine
			jmp nextline
		.elseif (byte ptr [eax] == PP_IGNORE)
			jmp nextline
		.elseif (byte ptr [eax] == PP_COMMENT)
			invoke AddComment, eax
			jmp nextline
		.endif
	.endif
	ret

GetNextTokenPP endp


;--- copy rest of line to destination

CopyLine proc
	.while (1)
		invoke GetNextTokenPP
		.break .if (!eax)
		invoke write, eax
		invoke write, CStr(" ")
	.endw
	invoke WriteComment
	invoke write, CStr(cr,lf)
	ret
CopyLine endp

IsName proc pszType:dword
	mov ecx, pszType
	mov al,[ecx]
	.if ((al >= 'A') && (al <= 'Z'))
		jmp istrue
	.elseif ((al >= 'a') && (al <= 'z'))
		jmp istrue
	.elseif ((al == '_') || (al == '?') || (al == '@'))
		jmp istrue
	.elseif ((al == '~') && (m_bIsClass))
		jmp istrue
	.endif
	xor eax,eax
	ret
istrue:
	mov eax, 1
	ret
IsName endp

;--- returns C if not

IsAlphaNumeric proc
	cmp al,'0'
	jb isfalse
	cmp al,'9'
	jbe istrue
IsAlpha::
	cmp al,'?'
	je istrue
	cmp al,'@'
	je istrue
	cmp al,'A'
	jb isfalse
	cmp al,'Z'
	jbe istrue
	cmp al,'_'
	je istrue
	cmp al,'a'
	jb isfalse
	cmp al,'z'
	ja isfalse
istrue:
	clc
	ret
isfalse:
	stc
	ret
IsAlphaNumeric endp

;--- returns: C if not true

IsNumOperator proc
	cmp al,'-'
	jz istrue
	cmp al,'+'
	jz istrue
	cmp al,'*'
	jz istrue
	cmp al,'/'
	jz istrue
	cmp al,'|'
	jz istrue
	cmp al,'&'
	jz istrue
	cmp ax,'>>'
	jz istrue
	cmp ax,'<<'
	jz istrue
	stc
	ret
istrue:
	clc
	ret

IsNumOperator endp

;--- translate operator in #define lines

TranslateOperator proc pszToken:ptr byte
	mov ecx, pszToken
	mov eax,[ecx]
	and eax, 0FFFFFFh
	.if (eax == ">>")
		mov eax, CStr(" shr ")
	.elseif (eax == "<<")
		mov eax, CStr(" shl ")
	.elseif (ax == "&")
		mov eax, CStr(" and ")
	.elseif (ax == "|")
		mov eax, CStr(" or ")
	.elseif (ax == "~")
		mov eax, CStr(" not ")
	.else
		mov eax, ecx
	.endif
	ret
TranslateOperator endp

;--- is current token a number (decimal or hexadecimal)
;--- edx = pszInp

IsNumber proc pszInp:ptr byte
	mov edx, pszInp
	mov al,[edx]
	.if ((al >= '0') && (al <= '9'))
		mov eax,1
	.else
		xor eax, eax
	.endif
	ret
IsNumber endp

IsReservedWord proc uses esi edi pszName:ptr byte

local	szWord[64]:byte

	mov esi, pszName
	mov ecx, sizeof szWord - 1
	lea edi, szWord
	mov pszName, edi
@@:
	lodsb
	stosb
	and al,al
	loopnz @B
	mov byte ptr [edi],0
	invoke _strlwr, addr szWord
	invoke _bsearch, addr pszName, g_ReservedWords.pItems,
		g_ReservedWords.numItems, 4, cmpproc
	ret
IsReservedWord endp

;--- if macro is found, return address of NAMEITEM
;--- or macro flags (then bit 0 of eax is set)

IsMacro proc uses esi pszName:ptr byte
	mov esi, g_ppKnownMacros
	.while (dword ptr [esi])
		lodsd
		invoke _strcmp, eax, pszName	;previously was lstrcmp!
		.if (!eax)
			lodsd
			or al,1
			ret
		.endif
		add esi, 4
	.endw
	invoke FindItem@List, g_pMacros, pszName
	ret
IsMacro endp

;--- test if its a number enclosed in braces

DeleteSimpleBraces	proc uses esi edi

local	sis:INPSTAT

	invoke SaveInputStatus, addr sis
	invoke GetNextTokenPP
	.if (eax && (byte ptr [eax] == '('))
		mov esi, eax
		invoke GetNextTokenPP
		mov edi, eax
		.if (edi)
			.if (byte ptr [edi] == '-')
				invoke GetNextTokenPP
				mov edi, eax
				.if (!eax)
					jmp @exit
				.endif
			.endif
			mov al,[edi]
			.if ((al >= '0') && (al <= '9'))
				invoke GetNextTokenPP
				.if (eax && (byte ptr [eax] == ")"))
					mov byte ptr [esi], PP_IGNORE
					mov byte ptr [eax], PP_IGNORE
				.endif
			.endif
		.endif
	.endif
@exit:
	invoke RestoreInputStatus, addr sis
	ret
DeleteSimpleBraces endp

;--- skip braces of "(" <number> ")" pattern

SkipSimpleBraces proc

local	sis:INPSTAT

	invoke SaveInputStatus, addr sis
	.repeat
		invoke IsName, m_pszIn
		.if (eax)
			invoke GetNextTokenPP
			.break .if (!eax)
		.else
			invoke DeleteSimpleBraces
		.endif
		invoke GetNextTokenPP
	.until (!eax)
	invoke RestoreInputStatus, addr sis
	ret
SkipSimpleBraces endp

IsString proc pszToken:LPSTR
	mov ecx, pszToken
	mov al,[ecx]
	.if (al == '"')
		jmp istrue
	.elseif (al >= '0' && al <= '9')
		inc ecx
		.while (byte ptr [ecx])
			.if (byte ptr [ecx] == ',')
				jmp istrue
			.endif
			inc ecx
		.endw
	.endif
	xor eax, eax
	ret
istrue:
	mov eax, 1
	ret
IsString endp

;--- for EQU invocation
;--- called by IsDefine

convertline proc uses edi esi pszName:LPSTR

local	bExpression:BOOLEAN
local	pszValue:LPSTR
local	pszOut:LPSTR
local	ppszItems:ptr LPSTR
local	dwCnt:DWORD
local	dwEsp:DWORD
local	dwTmp[2]:DWORD
local	sis:INPSTAT

	mov dwEsp, esp
	invoke GetNextTokenPP
	.if (eax)
		mov pszValue, eax
		invoke SaveInputStatus, addr sis
		mov bExpression, FALSE
		mov eax, pszValue
		.while (eax)
			mov edi, eax
			invoke IsString, eax
			.if (eax)
				mov bExpression, FALSE
				.break
			.endif
			mov eax,[edi]
			.if (al >= '0' && al <= '9')
				mov bExpression, TRUE
			.elseif (al == '(' || al == ')')
				;
			.else
				call IsAlpha	;ignore ALPHA
				.if (CARRY?)
					invoke IsNumOperator
					.if (CARRY?)
						mov bExpression, FALSE
						.break
					.else
						mov bExpression, TRUE
					.endif
				.endif
			.endif
			invoke GetNextTokenPP
		.endw
		invoke RestoreInputStatus, addr sis
		.if (!bExpression)
			invoke write, CStr(3Ch)
		.endif
		mov eax, m_pszOut
		mov pszOut, eax
		Create@Stacklist
		mov ppszItems, eax
		mov eax, pszValue
		mov dwCnt, 0
		.while (eax)
			mov edi, eax
			Add@Stacklist ppszItems, eax
			.if (dwCnt)
				invoke write, CStr(" ")
			.endif
			dprintf <"%u: item %s found",lf>, m_dwLine, edi
			inc dwCnt
			invoke TranslateOperator, edi
			invoke write, eax
			invoke GetNextTokenPP
		.endw
;------------------------ if equate is a simple text item
;------------------------ check if the value is a proto qualifier
;------------------------ if yes, add new equate to qualifier list
if ?DYNPROTOQUALS
		mov edi, pszOut
		.if (g_bUseDefProto && (byte ptr [edi] > '9'))
			invoke _strcmp, edi, CStr("__declspec ( dllimport )")
			.if (!eax)
				mov ecx, FQ_IMPORT
				call xxxx
			.else
				GetNumItems@Stacklist ppszItems
				mov ecx, eax
				xor esi, esi
				.while (ecx)
					push ecx
					GetItem@Stacklist ppszItems, esi
ifdef _DEBUG
					push eax
					invoke printf, CStr("getting stacklist item %X: %s",10), esi, eax
					pop eax
endif
					invoke FindItem@List, g_pQualifiers, eax
					.if (eax)
						mov ecx, [eax+4]
						call xxxx
					.endif
					pop ecx
					inc esi
					dec ecx
				.endw
			.endif
		.endif
endif
		.if (!bExpression)
			invoke write, CStr(3Eh)
		.endif
	.else
		invoke write, CStr("<>")
	.endif
	invoke WriteComment
	invoke write, CStr(cr,lf)
	mov esp, dwEsp
	ret
xxxx:
	.if (ecx & (FQ_IMPORT or FQ_STDCALL or FQ_CDECL))
		push ecx
		invoke FindItem@List, g_pQualifiers, pszName
		.if (!eax)
			invoke InsertItem, g_pQualifiers, pszName, 0
			.if (eax)
				mov dword ptr [eax+4],0
			.endif
		.endif
		pop ecx
		.if (eax)
			or [eax+4], ecx
		.endif
;		 invoke printf, CStr("qualifier %s attr %X added",10), pszName, ecx
	.endif
	retn

convertline endp

GetInterfaceName proc uses esi edi pszName:LPSTR, pszInterface:LPSTR
	mov esi, pszName
	mov edi, pszInterface
	mov cl,0
	.repeat
		lodsb
		.if (al != '_')
			inc cl
		.elseif (cl)
			mov al,0
		.endif
		stosb
	.until (!al)
	ret
GetInterfaceName endp

;--- check if macro is pattern "(this)->lpVtbl-><method>(this,...)"
;--- if yes, return name of THIS is eax and method name in edx

IsCObjMacro proc uses esi edi

local	sis:INPSTAT

	invoke SaveInputStatus, addr sis
	invoke GetNextTokenPP
	.if ((!eax) || (word ptr [eax] != '('))
		jmp @exit
	.endif
	invoke GetNextTokenPP	;get name of THIS
	.if (!eax)
		jmp @exit
	.endif
	mov esi, eax
	invoke IsName, eax
	.if (!eax)
		jmp @exit
	.endif
	invoke GetNextTokenPP
	.if ((!eax) || (word ptr [eax] != ')'))
		jmp @exit
	.endif
	invoke GetNextTokenPP
	.if ((!eax) || (word ptr [eax] != ">-"))
		jmp @exit
	.endif
	invoke GetNextTokenPP
	.if (!eax)
		jmp @exit
	.endif
	invoke _strcmp, eax, CStr("lpVtbl")
	.if (eax)
		jmp @exit
	.endif
	invoke GetNextTokenPP
	.if ((!eax) || (word ptr [eax] != ">-"))
		jmp @exit
	.endif
	invoke GetNextTokenPP	;get method name
	.if (!eax)
		jmp @exit
	.endif
	mov edi, eax
	invoke GetNextTokenPP
	.if ((!eax) || (word ptr [eax] != "("))
		jmp @exit
	.endif
	invoke GetNextTokenPP
	.if (!eax)
		jmp @exit
	.endif
	invoke _strcmp, eax, esi	;is THIS?
	.if (eax)
		jmp @exit
	.endif
	mov eax, esi
	mov edx, edi
	ret
@exit:
	invoke RestoreInputStatus, addr sis
	xor eax, eax
	ret
IsCObjMacro endp

SkipPPLine proc
	.repeat
		invoke GetNextTokenPP
	.until (!eax)
	ret
SkipPPLine endp

;--- size of output buffer pszNewType must be 256 bytes at least!

MakeType proc pszType:LPSTR, bUnsigned:DWORD, bLong:DWORD, pszNewType:LPSTR

	.if (!pszType)
		.if (bLong)
			mov pszType, CStr("long")
			mov bLong, 0
		.else
			mov pszType, CStr("int")
		.endif
	.endif
	mov eax, pszType
	.if (bUnsigned)
		invoke sprintf, pszNewType, CStr("unsigned %.246s"), pszType
		mov eax, pszNewType
	.elseif (bLong)
		invoke sprintf, pszNewType, CStr("long %.250s"), pszType
		mov eax, pszNewType
	.endif
	ret

MakeType endp

;--- skip typecasts in preprocessor lines

SkipCasts proc uses esi edi

local	pszToken:LPSTR
local	bIsName:BOOLEAN
local	bUnsigned:BOOLEAN
local	bLong:BOOLEAN
local	pszUnsigned:LPSTR
local	pszLong:LPSTR
local	pszPtr:LPSTR
local	sis:INPSTAT
local	sis2:INPSTAT
local	szType[128]:byte

	mov bIsName, FALSE
	invoke SaveInputStatus, addr sis
	.while (1)
		invoke GetNextTokenPP
		.break .if (!eax)
		mov pszToken, eax

;--- skip MACRO(type) patterns

		invoke IsName, eax
		.if (eax)
			mov bIsName, TRUE
			.continue
		.endif

;--- check for '(' ... <*> ')' pattern

		mov eax, pszToken
		.if ((byte ptr [eax] == '(') && (bIsName == FALSE))
			mov bUnsigned, FALSE
			mov bLong, FALSE
			invoke SaveInputStatus, addr sis2
nexttoken:
			invoke GetNextTokenPP
			mov edi, eax
			.if (eax)
				invoke _strcmp, eax, CStr("unsigned")
				.if (!eax)
					mov bUnsigned, TRUE
					mov pszUnsigned, edi
					jmp nexttoken
				.endif
				invoke _strcmp, edi, CStr("long")
				.if (!eax)
					mov bLong, TRUE
					mov pszLong, edi
					jmp nexttoken
				.endif
			.endif
			.if (eax)
				invoke GetNextTokenPP
				mov esi, eax
				mov pszPtr, NULL
				.if (esi && (byte ptr [esi] == '*'))
					mov pszPtr, esi
					invoke GetNextTokenPP
					mov esi, eax
				.endif
				.if (esi && (byte ptr [esi] == ')'))

					.if (bUnsigned || bLong)
						movzx ecx, bUnsigned
						movzx edx, bLong
						invoke MakeType, edi, ecx, edx, addr szType
						invoke TranslateType, eax, 0
					.else
						invoke TranslateType, edi, 0
					.endif
					.if (byte ptr [eax])
						invoke IsSimpleType, eax
					.endif
					.if (eax)
						mov byte ptr [esi], PP_IGNORE
						mov byte ptr [edi], PP_IGNORE
						mov eax, pszPtr
						.if (eax)
							mov byte ptr [eax], PP_IGNORE
						.endif
						.if (bUnsigned)
							mov eax, pszUnsigned
							mov byte ptr [eax], PP_IGNORE
						.endif
						.if (bLong)
							mov eax, pszLong
							mov byte ptr [eax], PP_IGNORE
						.endif
						mov eax, pszToken
						mov byte ptr [eax], PP_IGNORE
					.endif
				.endif
			.endif
			invoke RestoreInputStatus, addr sis2
		.endif
		mov bIsName, FALSE
	.endw
	invoke RestoreInputStatus, addr sis
	ret
SkipCasts endp

;--- #define has occured
;--- can be a constant or a macro
;--- esi=input token stream

IsDefine proc

local	bMacro:BOOLEAN
local	szComment[2]:BYTE
local	pszName:LPSTR
local	pszValue:LPSTR
local	pszParm:LPSTR
local	pszToken:LPSTR
local	dwParms:DWORD
local	pszThis:LPSTR
local	bIsCObj:DWORD
local	szInterface[128]:BYTE
local	szMethod[128]:BYTE

		push m_pszOut
		invoke GetNextTokenPP			;get the name of constant/macro
		.if (eax)
			mov pszName, eax
			mov word ptr szComment, 0
			invoke IsReservedWord, eax
			.if (eax)
				mov szComment, ';'
				.if (g_bWarningLevel > 0)
					invoke printf, CStr("%s, %u: reserved word '%s' used as equate/macro",lf),
						m_pszFileName, m_dwLine, pszName
					inc m_dwWarnings
				.endif
			.endif
			invoke SkipCasts
			invoke write, addr szComment
			invoke write, pszName
			mov eax, m_pszIn
			.if (word ptr [eax] == PP_MACRO)
				mov bMacro, TRUE
			.else
				mov bMacro, FALSE
			.endif
			.if (bMacro)
				invoke GetNextTokenPP	;skip PP_MACRO
				invoke GetNextTokenPP	;skip "("
				invoke write, CStr(" macro ")

;------------------------------------------ write the macro params
if 1
				invoke SkipSimpleBraces
endif
				mov dwParms, 0
				.while (1)
					invoke GetNextTokenPP
					.break .if (!eax)
					.break .if (byte ptr [eax] == ")")
					.if (byte ptr [eax] != ',')
						inc dwParms
						mov pszParm, eax
						invoke IsReservedWord, eax
						.if (eax && (g_bWarningLevel > 1))
							invoke printf, CStr("%s, %u: reserved word '%s' used as macro parameter",lf),
								m_pszFileName, m_dwLine, pszParm
							inc m_dwWarnings
						.endif
						mov eax, pszParm
					.endif
					invoke write, eax
				.endw
				invoke write, CStr(cr,lf)
				invoke write, addr szComment

;------------------------------------------- save macro name in symbol table
				invoke IsMacro, pszName
				.if (!eax)
					invoke InsertItem, g_pMacros, pszName, dwParms
				.endif
				
				invoke write, CStr(tab,"exitm ",3Ch)

;------------------------------------------ test if it is a "COBJMACRO"
				invoke IsCObjMacro
				mov bIsCObj, eax
				.if (eax)
					mov pszThis, eax
					push edx
					invoke GetInterfaceName, pszName, addr szInterface
					pop edx
					invoke TranslateName, edx, NULL
					invoke xprintf, CStr("vf(%s, %s, %s)"), pszThis, addr szInterface, eax
				.endif
				.while (1)
					invoke GetNextTokenPP
					.break .if (!eax)
					.continue .if ((bIsCObj) && (word ptr [eax] == ')'))
					invoke TranslateOperator, eax
					invoke write, eax
					invoke write, CStr(" ")
				.endw
				invoke write, CStr(3Eh,cr,lf)
				invoke write, addr szComment
				invoke write, CStr(tab,"endm",cr,lf)
			.else
				invoke write, CStr(tab,"EQU",tab)
				invoke SkipSimpleBraces
				invoke convertline, pszName
			.endif
		.endif
@exit:
		pop ecx
		.if (!g_bConstants)
			mov m_pszOut, ecx
			mov byte ptr [ecx],0
		.endif
		ret
IsDefine endp

;--- esi=input token stream

IsInclude proc uses esi edi

local	pszPath:dword

		invoke write, CStr(tab,"include ")
		invoke GetNextTokenPP
		.if (eax && (byte ptr [eax] == '<'))
			invoke GetNextTokenPP
		.endif
		mov pszPath, eax
		mov edi, m_pszOut
		mov esi, pszPath
		.if (esi)
			mov dh,0
			.if (byte ptr [esi] == '"')
				inc esi
				mov dh,'"'
			.endif
			.while (byte ptr [esi])
				lodsb
				.break .if (al == dh)
				.break .if (!al)
				stosb
			.endw
			mov ax,[edi-2]
			or	ah,20h
			.if (ax == "h.")
				.if (g_bProcessInclude)
					pushad
					mov al,0
					stosb
					invoke ProcessFile, m_pszOut, _this
					popad
				.endif
				dec edi
				dec edi
				mov eax,"cni."
				stosd
			.endif
			mov ax,0A0Dh
			stosw
		.endif
		mov m_pszOut, edi
		mov al,0
		stosb
		ret
IsInclude endp

IsError proc uses esi
		invoke write, CStr(".err ",3Ch)
		xor esi, esi
		.while (1)
			invoke GetNextTokenPP
			.break .if (!eax)
			.if (esi)
				push eax
				invoke write, CStr(" ")
				pop eax
			.endif
			invoke write, eax
			inc esi
		.endw
		invoke write, CStr(20h,3Eh,13,10)
		ret
IsError endp

IsPragma proc uses esi

local	sis:INPSTAT

		invoke SaveInputStatus, addr sis
		invoke GetNextTokenPP
		invoke _strcmp, eax, CStr("message")
		.if (eax)
			invoke RestoreInputStatus, addr sis
			jmp notmessage
		.endif
		invoke GetNextTokenPP	;skip '('
		.if (eax)
			invoke write, CStr("%echo ")
			xor esi, esi
			.while (1)
				invoke GetNextTokenPP
				.break .if ((!eax) || (byte ptr [eax] == ')'))
				.if (!esi)
					push eax
					invoke write, CStr(" ")
					pop eax
				.endif
				.if (byte ptr [eax] == '"')
					inc eax
					push eax
					invoke lstrlen, eax
					pop ecx
					mov byte ptr [ecx+eax-1],0
					mov eax, ecx
				.endif
				invoke write, eax
				inc esi
			.endw
			.if (eax)
				invoke SkipPPLine
			.endif
			mov ecx, m_pszOut
;------------------------------ check if last character is a ','
;------------------------------ this causes %echo to continue with next line!
			mov al,byte ptr [ecx-1]
			.if (al == ',')
				invoke write, CStr("'")
			.endif			  
			invoke write, CStr(cr,lf)
		.endif
		ret
notmessage:
		invoke write, CStr(";#pragma ")
		invoke CopyLine
		ret
IsPragma endp

TranslateIfExpression proc uses edi pszToken:dword

		mov eax, pszToken
		mov edi, offset g_szOpConvTab
		mov ecx, sizeOpConvTab
		.while (ecx)
			mov dx,word ptr [edi].OPCONV.wOp
			.if ([eax] == dx)
				mov eax,[edi].OPCONV.pszSubst
				.break
			.endif
			add edi, sizeof OPCONV
			dec ecx
		.endw
		ret
TranslateIfExpression endp

IncIfLevel proc

		.if (m_bIfLvl == ?MAXIFLEVEL)
			invoke printf, CStr("%s, %u: if nesting level too deep",lf),
				m_pszFileName, m_dwLine
			inc m_dwErrors
		.else
			inc m_bIfLvl
			movzx eax, m_bIfLvl
			mov m_bIfStack[eax],0
		.endif
		ret
IncIfLevel endp

IncElseLevel proc
		movzx eax, m_bIfLvl
		.if (eax)
			inc m_bIfStack[eax]
		.else
			invoke printf, CStr("%s, %u: else/elif without if",lf),
				m_pszFileName, m_dwLine
			inc m_dwErrors
		.endif
		ret
IncElseLevel endp

DecIfLevel proc
		.if (m_bIfLvl)
			dec m_bIfLvl
		.else
			invoke printf, CStr("%s, %u: endif without if",lf),
				m_pszFileName, m_dwLine
			inc m_dwErrors
		.endif
		ret
DecIfLevel endp

;--- #if/#elif

IfElseIf proc uses esi bMode:dword

local	pszToken:dword
local	pszNot:dword

		invoke SkipCasts
		invoke GetNextTokenPP
		mov pszToken, eax
		.if (eax)
			.if (word ptr [eax] == "!")
				mov pszNot, CStr("0 eq ")
				invoke GetNextToken
				mov pszToken, eax
			.else
				mov pszNot, CStr("")
			.endif
			invoke _strcmp, pszToken, CStr("defined")
			.if (!eax)
				mov esi, pszNot
				call getifexpr
				jmp @exit
			.endif
		.endif
		.if (!bMode)
			invoke write, CStr("if ")
		.else
			invoke write, CStr("elseif ")
		.endif
@exit:
		mov eax,pszToken
		.while (eax)
			invoke IsNumber, eax
			.if (eax)
				invoke write, edx
			.else
				invoke TranslateIfExpression, edx
				invoke write, eax
			.endif
			invoke GetNextTokenPP
		.endw
		invoke write, CStr(cr,lf)
		ret
getifexpr:
		.if (!m_bDefinedMac)
			mov m_bDefinedMac, TRUE
			invoke write, offset szMac_defined
		.endif
		.if (!bMode)
			invoke write, CStr("if ")
		.else
			invoke write, CStr("elseif ")
		.endif
		invoke write, esi
		invoke write, CStr("defined")
		invoke GetNextTokenPP
		mov pszToken, eax
		retn
IfElseIf endp

;--- #ifdef/#ifndef

IfdefIfndef proc pszCmd:LPSTR
		invoke SkipCasts
		invoke GetNextTokenPP
		.if (!eax)
			invoke printf, CStr("%s, %u: unexpected end of line",lf), m_pszFileName, m_dwLine
			inc m_dwErrors
			invoke write, CStr("if 0;")
		.else
			push eax
			invoke IsReservedWord, eax
			.if (eax)
				invoke write, CStr("if 0;")
			.endif
			invoke write, pszCmd
			invoke write, CStr(" ")
			pop eax
			invoke write, eax
		.endif
		invoke CopyLine
		ret
IfdefIfndef endp

;--- #else/#endif

ElseEndif proc pszCmd:LPSTR
		invoke write, pszCmd
		invoke write, CStr(" ")
		invoke CopyLine
		ret
ElseEndif endp

;----------------------------

IsIf proc
		invoke IncIfLevel
		invoke IfElseIf, 0
		ret
IsIf endp

IsElIf proc
		invoke IncElseLevel
		invoke IfElseIf, 1
		ret
IsElIf endp

IsIfdef proc
		invoke IncIfLevel
		invoke IfdefIfndef, CStr("ifdef")
		ret
IsIfdef endp

IsIfndef proc
		invoke IncIfLevel
		invoke IfdefIfndef, CStr("ifndef")
		ret
IsIfndef endp

IsElse proc
		invoke IncElseLevel
		invoke ElseEndif, CStr("else")
		ret
IsElse endp

IsEndif proc
		invoke DecIfLevel
		invoke ElseEndif, CStr("endif")
		ret
IsEndif endp

IsIfNP proc
		invoke IncIfLevel
		invoke SkipPPLine
		ret
IsIfNP endp

IsElIfNP proc
		invoke IncElseLevel
		invoke SkipPPLine
		ret
IsElIfNP endp

IsElseNP proc
		invoke IncElseLevel
		invoke SkipPPLine
		ret
IsElseNP endp

IsEndifNP proc
		invoke DecIfLevel
		invoke SkipPPLine
		ret
IsEndifNP endp

;--- add preprocessor lines

ParsePreProcs proc uses esi edi

local	pszToken:LPSTR

		invoke GetNextTokenPP
		.if (!eax)
			jmp @exit
		.endif
		mov pszToken, eax
		dprintf <"%u: ParsePreProc, preproc command %s found",lf>, m_dwLine, pszToken
;;		invoke SkipCasts

		mov eax, pszToken
		.if (!m_bSkipPP)
			mov edi, offset ppcmds
			invoke IsNewLine
			.if (!eax)
				invoke write, CStr(cr,lf)
			.endif
		.else
			mov edi, offset ppcmdsnp
		.endif
		.while ([edi].PPCMD.pszCmd)
			invoke _strcmp, pszToken, [edi].PPCMD.pszCmd
			.if (!eax)
				call [edi].PPCMD.pfnHandler
				jmp @exit
			.endif
			add edi, sizeof PPCMD
		.endw
		.if (m_bSkipPP)
			invoke SkipPPLine
		.else
			invoke xprintf, CStr(";#%s "), pszToken
			invoke CopyLine
		.endif
@exit:
		ret

ParsePreProcs endp

GetNextToken proc uses edi
		.if (m_bUseLastToken)
			mov m_bUseLastToken, FALSE
			mov eax, m_pszLastToken
			jmp @exit
		.endif
try_again:
		mov edi, m_pszIn
		mov ecx, -1
		mov al,0
		repnz scasb
		not ecx
		dec ecx
		xor eax, eax
		.if (!ecx)
			jmp @exit
		.endif
		mov eax, edi
		xchg eax, m_pszIn
		.if (word ptr [eax] == PP_EOL)
			inc m_dwLine
			mov m_bNewLine, TRUE
			mov eax, m_pszOut
			.if (byte ptr [eax-1] == lf)
				invoke WriteComment
				.if (eax)
					invoke write, CStr(cr,lf)
				.endif
			.endif
			jmp try_again
		.elseif (byte ptr [eax] == PP_COMMENT)
			.if (!m_bSkipPP)
				invoke AddComment, eax
			.endif
			jmp try_again
		.endif
		.if (m_bNewLine && (word ptr [eax] == '#'))
			push eax
			invoke WriteComment
			.if (eax)
				invoke write, CStr(cr,lf)
			.endif
			pop eax
			invoke ParsePreProcs
			jmp try_again
		.endif
@exit:
		mov m_bNewLine, FALSE
		ret
GetNextToken endp

PeekNextToken proc
local	sis:INPSTAT
		invoke SaveInputStatus, addr sis
		inc m_bSkipPP
		invoke GetNextToken
		push eax
		dec m_bSkipPP
		invoke RestoreInputStatus, addr sis
		pop eax
		ret
PeekNextToken endp

;--- check if token is a reserved name, if yes, add a '_' suffix
;--- return translated name in eax, edx=1 if translation occured

TranslateName proc uses esi pszName:LPSTR, pszOut:LPSTR
		
		invoke IsReservedWord, pszName
		.if (eax)		 
			mov esi, pszOut
			.if (!esi)
				mov esi, offset g_szTemp
			.endif
			invoke lstrcpy, esi, pszName
			invoke lstrcat, esi, CStr("_")
			mov eax, esi
			mov edx, 1
			ret
		.endif
		xor edx, edx
		mov eax, pszName
		ret
TranslateName endp

WriteExpression proc uses esi pExpression:ptr LPSTR
		GetNumItems@Stacklist pExpression
		mov ecx, eax
		.if (ecx)
			xor esi, esi
			.while (ecx)
				push ecx
				GetItem@Stacklist pExpression, esi
				invoke write, eax
				pop ecx
				dec ecx
				inc esi
			.endw
		.else
			invoke write, CStr("0")
		.endif
		ret
WriteExpression endp

;--- pszName may be NULL

AddMember proc pszType:LPSTR, pszName:LPSTR, pszDup:ptr byte, bIsStruct:dword
		dprintf <"%u: AddMember %s %s",lf>,m_dwLine, pszType, pszName
		.if (pszName)
			invoke TranslateName, pszName, NULL
			.if (edx && (g_bWarningLevel > 1))
				push eax
				invoke printf, CStr("%s, %u: reserved word '%s' used as struct/union member",lf),
					m_pszFileName, m_dwLine, pszName
				inc m_dwWarnings
				pop eax
			.endif
			invoke write, eax
		.endif
		invoke write, CStr(tab)
		movzx ecx, g_bUntypedMembers
		invoke TranslateType, pszType, ecx
		mov pszType, eax
		invoke write, eax
		.if (pszDup)
			invoke write, CStr(" ")
			invoke WriteExpression, pszDup
			Destroy@Stacklist pszDup
			invoke write, CStr(" dup ",28h)
		.else
			invoke write, CStr(tab)
		.endif
		mov eax, bIsStruct
		.if (!eax)
			invoke IsStructure, pszType 
		.endif
		.if (eax)
			invoke write, CStr("<>")
		.else
			invoke write, CStr("?")
		.endif
		.if (pszDup)
			invoke write, CStr(29h) 	;")"
		.endif
		invoke WriteComment
		invoke write, CStr(cr,lf)
		ret
AddMember endp

;--- preserve all registers
;--- inp: INPSTAT in ecx
;--- return C if current if level is NOT active

IsIfLevelActive proc
		pushad
		movzx eax, [ecx].INPSTAT.bIfLvl
		mov dl,[ecx].INPSTAT.bIfStack[eax]
		mov dh,m_bIfStack[eax]
		.if ((al == m_bIfLvl) && (dl != dh))
			stc
		.else
			clc
		.endif
		popad
		ret
IsIfLevelActive endp

;--- find name of a struct/union, if any
;--- use pszStructName if name is a macro
;--- out: eax = struct name
;---	  edx = flags (if name is a macro)

GetStructName proc pszStructName:LPSTR

local	dwCntBrace:dword
local	pszName:LPSTR
local	dwFlags:DWORD
local	sis:INPSTAT

		dprintf <"%u: GetStructName enter",lf>, m_dwLine
		mov pszName, NULL
		mov dwFlags, 0
		invoke SaveInputStatus, addr sis
		inc m_bSkipPP
		mov dwCntBrace, 1
		.while (dwCntBrace)
			invoke GetNextToken
			.break .if (!eax)
			lea ecx, sis
			invoke IsIfLevelActive
			.continue .if (CARRY?)			  
			.if (word ptr [eax] == '{')
				inc dwCntBrace
			.elseif (word ptr [eax] == '}')
				dec dwCntBrace
			.endif
		.endw
		.if (eax)
			invoke GetNextToken
			.if (eax && (byte ptr [eax] != ';'))
				.if (byte ptr [eax] == '*')
					jmp @exit
				.endif
				mov pszName,eax
;---------------------------------- there may come a type qualifier or a '*'				
;---------------------------------- in which case there is no name
				invoke ConvertTypeQualifier, eax
				.if (!byte ptr [eax])
					mov pszName, NULL
					jmp @exit
				.endif
				invoke IsMacro, pszName
				.if (eax)
					mov dwFlags, eax
					push m_pszOut
					mov ecx, pszStructName
					mov m_pszOut, ecx
					invoke MacroInvocation, pszName, eax, FALSE
					pop m_pszOut
					mov eax, pszStructName
					mov pszName, eax
				.endif
				dprintf <"%u: GetStructName, end of struct %s found",lf>, m_dwLine, pszName
			.endif
		.endif
		.if (!pszName)
			dprintf <"%u: GetStructName, no name found",lf>, m_dwLine
		.endif
@exit:
		dprintf <"%u: GetStructName exit",lf>, m_dwLine
		dec m_bSkipPP
		invoke RestoreInputStatus, addr sis
		mov eax, pszName
		mov edx, dwFlags
		ret

GetStructName endp


HasVTable proc

local	dwRC:DWORD
local	dwCntBrace:dword
local	sis:INPSTAT

		dprintf <"%u: HasVTable enter",lf>, m_dwLine
		invoke SaveInputStatus, addr sis
		inc m_bSkipPP
		mov dwCntBrace, 1
		mov dwRC, FALSE
		.while (dwCntBrace)
			invoke GetNextToken
			.break .if (!eax)
			lea ecx, sis
			invoke IsIfLevelActive
			.continue .if (CARRY?)			  
			.if (word ptr [eax] == '{')
				inc dwCntBrace
			.elseif (word ptr [eax] == '}')
				dec dwCntBrace
			.elseif ((dwCntBrace == 1) && (byte ptr [eax] == 'v'))
				invoke _strcmp, eax, CStr("virtual")
				.if (!eax)
					mov dwRC, TRUE
					.break
				.endif
			.endif
		.endw
		dec m_bSkipPP
		invoke RestoreInputStatus, addr sis
		mov eax, dwRC
		ret
HasVTable endp

;--- determine if it is a "function" or "function ptr" declaration

IsFunctionPtr proc

local	dwCntBrace:dword
local	bRC:dword
local	sis:INPSTAT

		invoke SaveInputStatus, addr sis
		inc m_bSkipPP
		mov dwCntBrace, 1
		mov bRC, FALSE
		.while (dwCntBrace)
			invoke GetNextToken
			.break .if (!eax)
			lea ecx, sis
			invoke IsIfLevelActive
			.continue .if (CARRY?)			  
			.if (word ptr [eax] == '(')
				inc dwCntBrace
			.elseif (word ptr [eax] == ')')
				dec dwCntBrace
			.endif
		.endw
		.if (eax)
			invoke GetNextToken
			.if (eax && (byte ptr [eax] == '('))
				mov bRC,TRUE
			.endif
		.else
			dprintf <"%s, %u: unexpected eof",lf>, m_pszFileName, m_dwLine
		.endif
@exit:
		dec m_bSkipPP
		invoke RestoreInputStatus, addr sis
		mov eax, bRC
		ret

IsFunctionPtr endp

;--- determine if current item is a "function" declaration
;--- required if keyword "struct" has been found in input stream
;--- may be a struct declaration or a function returning a struct (ptr)
;--- workaround:
;--- + if "*" is found before next ";" or ",", it is a function
;--- + if "(" is found before next ";" or ",", it is a function
;--- + if "{" is found before next ";" or ",", it is a structure

IsFunction proc

local	bRC:dword
local	sis:INPSTAT

		invoke SaveInputStatus, addr sis
		inc m_bSkipPP
		mov bRC, FALSE
		.while (1)
			invoke GetNextToken
			.break .if (!eax)
			lea ecx, sis
			invoke IsIfLevelActive
			.continue .if (CARRY?)			  
			mov cl,[eax]
			.break .if ((cl == ';') || (cl == ',') || (cl == "{"))
			.if ((cl == '*') || (cl == '('))
				mov bRC, TRUE
				.break
			.endif
		.endw
@exit:		  
		dec m_bSkipPP
		invoke RestoreInputStatus, addr sis
		mov eax, bRC
		ret
IsFunction endp

IsRecordEnd proc

local	bRC:dword
local	sis:INPSTAT

		invoke SaveInputStatus, addr sis
		inc m_bSkipPP
		mov bRC, TRUE
		.while (1)
			invoke GetNextToken
			.break .if (!eax)
			lea ecx, sis
			invoke IsIfLevelActive
			.continue .if (CARRY?)			  
			mov cl,[eax]
			.break .if (cl == ';')
			.break .if (cl == ',')
			.if (cl == ':')
				mov bRC, FALSE
				.break
			.endif
		.endw
@exit:		  
		dec m_bSkipPP
		invoke RestoreInputStatus, addr sis
		mov eax, bRC
		ret
IsRecordEnd endp

;--- skip name of a struct/union

SkipName proc pszName:LPSTR, dwNameFlags:DWORD

		.if (pszName)
			invoke GetNextToken	;skip name
			mov eax, dwNameFlags
			.if (eax)
				invoke PeekNextToken
				.if (eax && (word ptr [eax] == '('))
					.while (1)
						invoke GetNextToken
						.break .if (!eax)
						.break .if (word ptr [eax] == ')')
					.endw
				.endif
			.endif
		.endif
		ret
SkipName endp

IsPublicPrivateProtected proc pszToken:LPSTR

		invoke _strcmp, pszToken, CStr("private")
		.if (eax)
			invoke _strcmp, pszToken, CStr("public")
			.if (eax)
				invoke _strcmp, pszToken, CStr("protected")
			.endif
		.endif
		and eax, eax
		sete al
		movzx eax,al
		ret
IsPublicPrivateProtected endp

;--- returns eax == 1 if union/struct/class
;--- edx == 1 if class

IsUnionStructClass proc uses esi pszToken:LPSTR
		xor esi, esi
		invoke _strcmp, pszToken, CStr("union")
		.if (eax)
			invoke _strcmp, pszToken, CStr("struct")
			.if (eax)
				invoke _strcmp, pszToken, CStr("class")
				inc esi
			.endif
		.endif
		and eax, eax
		sete al
		movzx eax,al
		mov edx, esi
		ret
IsUnionStructClass endp

;--- get a variable declaration
;--- <type> name<[]> , followed by ";" or "," or "{"
;--- type: 
;--- <unsigned> <stdcall?> typename <<far|near> *>
;--- a C++ syntax may be found as well:
;--- <type> name(...)< ; | {...}>

;--- bMode:
;---  DT_STANDARD = standard (union|struct)
;---  DT_EXTERN = extern
;---  DT_ENUM = enum
;--- out: eax=next token

GetDeclaration proc pszToken:LPSTR, pszParent:LPSTR, bMode:DWORD

local	bBits:BYTE
local	bPtr:BYTE
local	bFunction:BOOLEAN
local	bIsVirtual:BOOLEAN
local	bUnsigned:BOOLEAN
local	bLong:BOOLEAN
local	bStatic:BOOLEAN
local	bStruct:SBYTE
local	dwCnt:DWORD
local	dwRes:DWORD
local	dwPtr:DWORD
local	dwBits:DWORD
local	dwNameFlags:DWORD
local	pszType:LPSTR
local	pszName:LPSTR
local	pszDup:LPSTR
local	pszRecordType:LPSTR
local	pszBits:LPSTR
local	pszEndToken:LPSTR
local	dwEsp:DWORD
local	szStructName[?MAXSTRUCTNAME]:byte
local	szRecord[64]:byte
local	szType[256]:byte
local	szTmp[8]:byte
local	szName[128]:byte

		.if (!pszParent)
			mov pszParent, CStr("")
		.endif
		push m_pszStructName
		mov dwEsp, esp
		mov eax, pszParent
		mov m_pszStructName, eax

		mov bBits,FALSE
		mov pszType, NULL
		mov dwRes,0
		mov bUnsigned, FALSE
		mov bLong, FALSE
		mov bStruct, FALSE
		mov bStatic, FALSE
		mov dwBits,0
nextscan:
		mov bFunction,FALSE
		mov bIsVirtual, FALSE
		mov pszBits, NULL
		mov dwPtr, 0
		mov pszName, NULL
		mov pszDup, NULL

		.while (1)
			mov eax, pszToken
			.break .if (!eax)
			.break .if (byte ptr [eax] == ';')
			.break .if (byte ptr [eax] == '}')
			.break .if (byte ptr [eax] == ',')
			
			invoke _strcmp, pszToken, CStr("union")
;--------------------------------------------------------- union
			.if (!eax)
				dprintf <"%u, GetDeclaration: %s.union found",lf>, m_dwLine, pszParent
				invoke write, CStr("union")
				invoke GetNextToken
				.if (!eax)
					jmp error
				.endif
				mov pszToken, eax
				invoke IsName, eax
				.if (eax)
					invoke GetNextToken
					.if (!eax)
						jmp error
					.endif
				.else
					mov eax, pszToken
				.endif
				.if (word ptr [eax] == '{')
					invoke GetStructName, addr szStructName
					mov pszName, eax
					mov dwNameFlags, edx
					.if (eax)
						invoke write, CStr(" ")
						invoke TranslateName, pszName, NULL
						invoke write, eax
					.endif
					invoke write, CStr(cr,lf)
					invoke getblock, pszName, DT_STANDARD, pszParent
					.if (!eax)
						jmp done
					.endif
					invoke SkipName, pszName, dwNameFlags
				.else
					invoke printf, CStr("%s, %u: union without block",lf), m_pszFileName, m_dwLine
					inc m_dwErrors
					invoke write, CStr(cr,lf)
				.endif
				mov pszType, NULL
				mov pszName, NULL
				invoke write, CStr("ends",cr,lf)
				dprintf <"%u: end of union",lf>, m_dwLine
				jmp nextitem
			.endif
			invoke _strcmp, pszToken, CStr("struct")
			.if (!eax)
;--------------------------------------------------------- struct
				dprintf <"%u, GetDeclaration: %s.struct found",lf>, m_dwLine, pszParent
				invoke GetNextToken
				.if (!eax || (word ptr [eax] == ';'))
					jmp error
				.endif
				dprintf <"%u, GetDeclaration: %s.struct, next token %s",lf>, m_dwLine, pszParent, eax
				.if (word ptr [eax] != '{')
					mov pszName, eax
					invoke PeekNextToken
					.if (eax && word ptr [eax] == '{')
						invoke GetNextToken
					.else
						xor eax, eax
						xchg eax, pszName
					.endif
				.endif
				.if (word ptr [eax] == '{')
					invoke write, CStr("struct")
					invoke GetStructName, addr szStructName
					.if (eax)
						mov pszName, eax
					.endif
					mov dwNameFlags, edx
					.if (eax)
						invoke write, CStr(" ")
						invoke TranslateName, pszName, NULL
						invoke write, eax
					.endif
					invoke write, CStr(cr,lf)
					invoke getblock, pszName, DT_STANDARD, pszParent
					.if (!eax)
						jmp done
					.endif
					invoke SkipName, pszName, dwNameFlags
					invoke write, CStr("ends",cr,lf)
					dprintf <"%u: end of struct",lf>, m_dwLine
				.elseif (word ptr [eax] == '*')
					inc dwPtr
				.else
;----------------------------------------- found "struct tagname                
					mov pszType, eax		;name of structure
					mov pszName, NULL
					mov bPtr, 0
					invoke IsName, eax
					.if (eax)
						.while (1)
							invoke GetNextToken
							.if (!eax)
								jmp error
							.endif
							mov cl,[eax]
							.break .if ((cl == ';') || (cl == ','))
							.if (word ptr [eax] == '*')
								inc bPtr
							.else
								invoke ConvertTypeQualifier, eax
								.continue .if (!byte ptr [eax])
								push eax
								invoke IsName, eax
								pop ecx
								.if (eax)
									mov pszName, ecx
									.break
								.endif
							.endif
						.endw
						.if (pszName)
							.if (pszType && (!bPtr))
								invoke xprintf, CStr("%s %s <>",cr,lf),pszName, pszType
							.else
								invoke xprintf, CStr("%s DWORD ?",cr,lf),pszName
							.endif
						.else
							mov bStruct, TRUE
							jmp nextitem
;							invoke printf, CStr("%s, %u: unexpected item %s",lf),
;								m_pszFileName, m_dwLine, eax
						.endif
					.else
						invoke printf, CStr("%s, %u: unexpected item %s after 'struct'",lf),
							m_pszFileName, m_dwLine, pszType
						inc m_dwErrors
					.endif
				.endif
				mov pszType, NULL
				mov pszName, NULL
				jmp nextitem
			.endif
;------------------------------------------------- end union+struct

			invoke _strcmp, pszToken, CStr("unsigned")
			.if (!eax)
				mov bUnsigned, TRUE
				jmp nextitem
			.endif
			invoke _strcmp, pszToken, CStr("signed")
			.if (!eax)
				mov bUnsigned, FALSE
				jmp nextitem
			.endif
			invoke _strcmp, pszToken, CStr("long")
			.if (!eax)
				mov bLong, TRUE
				jmp nextitem
			.endif
			invoke _strcmp, pszToken, CStr("static")
			.if (!eax)
				mov bStatic, TRUE
				jmp nextitem
			.endif

;-------------------- check for pattern "public:","private:","protected:"
			invoke IsPublicPrivateProtected, pszToken
			.if (eax)
				invoke PeekNextToken
				.if (eax && (word ptr [eax] == ':'))
					invoke GetNextToken
					invoke xprintf, CStr(";%s:",cr,lf), pszToken
					jmp nextitem
				.endif
			.endif
			invoke _strcmp, pszToken, CStr("operator")
			.if (!eax)
;--------------------------------------------------------- operator
				invoke printf, CStr("%s, %u: C++ syntax ('operator') found",lf),
					m_pszFileName, m_dwLine
				.while (1)
					invoke GetNextToken
					mov pszToken, eax
					.break .if (!eax)
					.break .if (word ptr [eax] == ';')
					.if (word ptr [eax] == '{')
						push esi
						mov esi, 1
						.while (esi)
							invoke GetNextToken
							.break .if (!eax)
							mov pszToken, eax
							.if (word ptr [eax] == '{')
								inc esi
							.elseif (word ptr [eax] == '}')
								dec esi
							.endif
						.endw
						pop esi
						.break
					.endif
				.endw
				mov pszType, NULL
				mov pszName, NULL
				inc m_dwErrors
				.break
			.endif
;--------------------------------------------------------- friend
			invoke _strcmp, pszToken, CStr("friend")
			.if (!eax)
				jmp nextitem
			.endif
			invoke _strcmp, pszToken, CStr("virtual")
			.if (!eax)
				mov bIsVirtual, TRUE
				jmp nextitem
			.endif


			invoke IsMacro, pszToken
			.if (eax)
				.if (bMode == DT_ENUM)
					invoke MacroInvocation, pszToken, eax, FALSE
					mov pszName, CStr("")
				.else
					invoke MacroInvocation, pszToken, eax, TRUE
				.endif
				.if (eax)
					jmp nextitem
				.endif
			.endif

			mov eax, pszToken
			.if (word ptr [eax] == '=')
				.if (bMode == DT_ENUM)
					jmp nextitem
				.elseif (bMode == DT_EXTERN)
					.while (1)
						invoke GetNextToken
						.break .if ((!eax) || (word ptr [eax] == ';') || (word ptr [eax] == ','))
					.endw
					mov pszToken, eax
					.continue
				.endif
			.endif

			.if (word ptr [eax] == ':')
				invoke GetNextToken
				.if (!eax)
					jmp error
				.endif
				mov pszBits, eax
				jmp nextitem
			.endif

			.if (word ptr [eax] == '[')
				Create@Stacklist
				mov pszDup, eax
				.while (1)
					invoke GetNextToken
					.if ((!eax) || (byte ptr [eax] == ';'))
						jmp error
					.endif
					.break .if (word ptr [eax] == ']')
					Add@Stacklist pszDup, eax
				.endw
				jmp nextitem
			.endif	;'['

			.if ((word ptr [eax] == '~') && (m_bIsClass))
				invoke GetNextToken
				.if (!eax)
					jmp error
				.endif
				mov szName,'~'
				invoke lstrcpy, addr szName+1, eax
				lea eax, szName
				mov pszToken, eax
			.endif

			.if ((word ptr [eax] == '(') && (bMode != DT_ENUM))
				invoke IsFunctionPtr
				.if (eax)
					dprintf <"%u: GetDeclaration, function ptr found",lf>, m_dwLine
					invoke ParseTypedefFunctionPtr, pszParent
					.if (!eax)
;----------------- clear dereference count (was part of function return type)
						mov dwPtr, 0
						mov pszName, edx
						.if (m_bIsInterface)
							mov pszName, NULL
							mov pszType, NULL
						.elseif (g_bUntypedMembers)
							mov pszType, CStr("DWORD")
						.else
							invoke sprintf, addr szType, CStr("p%s_%s"),pszParent, pszName
							lea eax, szType
							mov pszType, eax
						.endif
					.else
						jmp error
					.endif
				.else
;;					mov eax, pszType
;;					.if (!eax)
						mov eax, pszName
;;					.endif
					.if (eax)
						dprintf <"%u: GetDeclaration, function %s found",lf>, m_dwLine, eax
						invoke ParseTypedefFunction, eax, TRUE, pszParent
						.if (bMode == DT_STANDARD)
							mov pszName, NULL
							mov pszType, NULL
						.endif
						.if (bIsVirtual)
							invoke PeekNextToken
							.if (eax && (byte ptr [eax] == '='))
								invoke GetNextToken
								invoke GetNextToken
							.endif
						.endif
					.else
						jmp error
					.endif
				.endif
				mov bFunction, TRUE
				jmp nextitem
			.endif	;'('

			.if ((word ptr [eax] == '*') || (word ptr [eax] == '&'))
				inc dwPtr
				jmp nextitem
			.endif

			.if (bMode != DT_ENUM)
				invoke ConvertTypeQualifier, pszToken
				.if (!byte ptr [eax])
					jmp nextitem
				.endif
				mov pszToken, eax
			.else
				.if (!pszType)
					invoke TranslateName, pszToken, NULL
					mov pszType, eax
					invoke write, eax
					invoke write, CStr(" = ")
				.else
					mov eax, pszToken
					mov pszName, eax
					invoke TranslateOperator, eax
					invoke write, eax
					mov eax,pszToken
					.if (byte ptr [eax] >= '0')
						invoke atol, pszToken
						inc eax
						mov m_dwEnumValue, eax
					.endif
					invoke write, CStr(" ")
				.endif
				jmp nextitem
			.endif
			invoke IsName, pszToken
			.if (eax)
				mov ecx, pszName
				.if (ecx)
					mov pszType, ecx
				.endif
				mov eax, pszToken
				mov pszName, eax
			.else
				jmp error
			.endif
nextitem:
			invoke GetNextToken
			mov pszToken, eax
		.endw
		mov pszEndToken, eax
		.if ((bMode == DT_EXTERN) || (bStatic))
			.if (pszName)
				invoke TranslateName, pszName, NULL
				.if (bStatic)
					invoke xprintf, CStr(";externdef syscall ?%s@%s@@___"), eax, pszParent
				.else
					invoke write, eax
				.endif
				invoke write, CStr(": ")
				.while (dwPtr)
					invoke write, CStr("ptr ")
					dec dwPtr
				.endw
				.if (bFunction)
					invoke write, CStr("near")
				.else
					movzx ecx, bUnsigned
					movzx edx, bLong
					invoke MakeType, pszType, ecx, edx, addr szType
					mov pszType, eax
;;					  invoke printf, CStr("GetDeclaration extern: type = %s",lf),pszType
					movzx ecx, g_bUntypedMembers
					invoke TranslateType, pszType, ecx
					invoke write, eax
				.endif
			.endif
			invoke write, CStr(cr,lf)
		.elseif (bMode == DT_ENUM)
			.if (pszType && (!pszName))
				invoke sprintf, addr szTmp, CStr("%u"),m_dwEnumValue
				invoke write, addr szTmp
				inc m_dwEnumValue
			.endif
			invoke write, CStr(cr,lf)
		.else
;------------------------------------- bitfield start
			.if (pszBits)
;--- it is possible that NO name is supplied for a record field!
				.if (!pszName)
					invoke sprintf, addr szName, CStr("res%u"),dwRes
					inc dwRes
					lea eax, szName
					mov pszName, eax
				.endif
				.if (!bBits)
					invoke sprintf, addr szRecord, CStr("%s_R%u"), pszParent, m_dwRecordNum
					inc m_dwRecordNum
					.if (!g_bNoRecords)
						invoke write, addr szRecord
						invoke write, CStr(tab,"RECORD",tab)
					.endif
					mov bBits,TRUE
					movzx ecx, bUnsigned
					movzx edx, bLong
					invoke MakeType, pszType, ecx, edx, addr szType
					mov pszType, eax
					invoke TranslateType, pszType, 0
					mov pszRecordType, eax
					dprintf <"%u: new Bitfield: %s",lf>, m_dwLine, pszRecordType
				.endif
				invoke TranslateName, pszName, NULL
				.if (!g_bNoRecords)
					invoke write, eax
					invoke write, CStr(":")
					invoke write, pszBits
					dprintf <"%u: new bits: %s",lf>, m_dwLine, pszName
				.else
					invoke atol, pszBits
					mov ecx, dwBits
					xor edx, edx
					.while (eax)
						bts edx, ecx
						inc ecx
						dec eax
					.endw
					mov dwBits, ecx
					invoke xprintf, CStr("%s_%s equ 0%xh",cr,lf), addr szRecord, pszName, edx
				.endif
				invoke IsRecordEnd
				.if (eax)
					.if (!g_bNoRecords)
						invoke write, CStr(cr,lf)
					.endif
					.if (g_bRecordsInUnions)
						invoke write, CStr("union",cr,lf,tab)
						invoke write, pszRecordType
						invoke write, CStr(tab,"?",cr,lf)
					.elseif (g_bNoRecords)
						invoke xprintf, CStr("%s",tab,"%s",tab,"?",cr,lf),addr szRecord, pszRecordType
					.endif
					.if (!g_bNoRecords)
						invoke write, CStr(tab)
						invoke write, addr szRecord
						invoke write, CStr(" <>",cr,lf)
					.endif
					.if (g_bRecordsInUnions)
						invoke write, CStr("ends",cr,lf)
					.endif
				.else
					.if (!g_bNoRecords)
						invoke write, CStr(",")
					.endif
					invoke GetNextToken
					mov pszToken, eax
					mov ecx, pszEndToken
					.if (ecx && (byte ptr [ecx] == ';'))
						mov pszType, NULL
					.endif
					jmp nextscan
				.endif
;------------------------------------- bitfield end

			.elseif (pszName)
				.if (dwPtr)
					mov pszType, CStr("DWORD")
				.else
					.if (!pszType)
						invoke IsStructure, pszName
						.if (eax)
							xor eax, eax
							xchg eax, pszName
							mov pszType, eax
						.endif
					.endif
					movzx ecx, bUnsigned
					movzx edx, bLong
					invoke MakeType, pszType, ecx, edx, addr szType
					mov pszType, eax
				.endif
				invoke AddMember, pszType, pszName, pszDup, bStruct
				mov ecx, pszToken
				.if (ecx && byte ptr [ecx] == ',')
					invoke GetNextToken
					mov pszToken, eax
					jmp nextscan
				.endif
			.endif
		.endif
done:
		mov esp, dwEsp
		mov eax, pszToken
		ret
error:
		mov esp, dwEsp
		pop m_pszStructName
		invoke printf, CStr("%s, %u: unexpected item %s.%s",lf),
			m_pszFileName, m_dwLine, pszParent, pszToken
		inc m_dwErrors
		mov eax, pszToken
		ret
GetDeclaration endp

;--- get members of a block (structure, union, enum)
;--- esi: input tokens
;--- dwMode:
;---  DT_STANDARD: variable declaration in struct/union
;---  DT_EXTERN: extern declaration
;---  DT_ENUM: enum declaration
;--- out: eax == 1: ok
;---      eax == 0: skip further block processing


getblock proc uses esi pszStructName:LPSTR, dwMode:DWORD, pszParent:LPSTR

local	wIf:WORD

		movzx eax, m_bIfLvl
		mov ah,m_bIfStack[eax]
		mov wIf,ax

		.if (pszStructName)
			mov m_dwRecordNum, 0
		.endif
		mov esi, 1
		.while (esi)
			invoke GetNextToken
			.break .if (!eax)
			movzx ecx, m_bIfLvl
			mov ch, m_bIfStack[ecx]
			.if ((cl == byte ptr wIf) && (ch != byte ptr wIf+1))
				mov m_pszLastToken, eax
				mov m_bUseLastToken, TRUE
				xor eax, eax
				jmp @exit
			.endif
			.if (word ptr [eax] == '{')
				inc esi
				.continue
			.elseif (word ptr [eax] == '}')
				dec esi
				.continue
			.endif
			.if (pszStructName)
				invoke GetDeclaration, eax, pszStructName, dwMode
			.else
				invoke GetDeclaration, eax, pszParent, dwMode
			.endif
			.break .if (!eax)
			.if (word ptr [eax] == '}')
				dec esi
			.endif
		.endw
		mov eax, 1
@exit:
		dprintf <"%u: getblock %s, end of struct found [%u]",lf>,m_dwLine, pszStructName, eax
		ret

getblock endp

;------- check out if there come some
;------- pointer definitions behind

GetFurtherTypes proc pszType:LPSTR, pszTag:LPSTR, pszToken:LPSTR

local	bPtr:byte
local	pszName:LPSTR

		mov bPtr, 0
		mov pszName, NULL
		.while (1)
			mov eax, pszToken
			.if ((byte ptr [eax] == ',') || (byte ptr [eax] == ';'))
				.if (pszName)
					push eax
					mov eax, pszType
					.if (!eax)
						mov eax, pszTag
					.endif
					dprintf <"%u: GetFurtherTypes '%s %s'",lf>, m_dwLine, pszName, eax
					push eax
;--------------------------------- comment out forward declarations
					.if (!bPtr)
						invoke lstrcmp, pszName, eax
						.if (!eax)
							invoke write, CStr(";")
						.endif
					.endif
					invoke write, pszName
					invoke write, CStr(" typedef ")
					.while (bPtr)
						invoke write, CStr("ptr ")
						dec bPtr
					.endw
					pop eax
					invoke write, eax
					invoke write, CStr(cr,lf)
					pop eax
				.endif
				.break .if (byte ptr [eax] == ';')
				mov pszName, NULL
				mov bPtr, 0
			.elseif (byte ptr [eax] == '*')
				inc bPtr
			.else
				invoke ConvertTypeQualifier, pszToken
				.if (byte ptr [eax])
					mov pszName, eax
				.endif
			.endif
nextitem:
			invoke GetNextToken
			.if (!eax)
				mov eax,12
				jmp error
			.endif
			mov pszToken, eax
		.endw
		.if (pszName)
			invoke write, CStr(cr,lf)
		.endif
		xor eax, eax
error:
		ret
GetFurtherTypes endp

HasVirtualBase proc uses esi pszInherit:ptr
		GetNumItems@Stacklist pszInherit
		mov ecx, eax
		xor esi, esi
		.while (ecx)
			push ecx
			GetItem@Stacklist pszInherit, esi
			invoke _strcmp, eax, CStr("virtual")
			.if (!eax)
				mov eax, 1
				ret
			.endif
			pop ecx
			dec ecx
			inc esi
		.endw
		xor eax, eax
		ret
HasVirtualBase endp

WriteInherit proc uses esi pszInherit:ptr, bPreClass:BOOL

local	bVirtual:BOOLEAN
local	bVbtable:BOOLEAN
local	pszToken:LPSTR

		GetNumItems@Stacklist pszInherit
		mov ecx, eax
		xor esi, esi
		mov bVirtual, FALSE
		mov bVbtable, FALSE
		.while (ecx)
			push ecx
			GetItem@Stacklist pszInherit, esi
			mov pszToken, eax
			invoke _strcmp, eax, CStr("virtual")
			.if (!eax)
				.if (bPreClass && (!bVbtable))
					invoke write, CStr(tab,"DWORD ?",tab,";`vbtable'",cr,lf)
					mov bVbtable, TRUE
				.endif
				mov bVirtual, TRUE
			.else
				invoke IsPublicPrivateProtected, pszToken
				.if (eax)
					.if (bPreClass)
						invoke xprintf, CStr(";%s:",cr,lf),pszToken
					.endif
				.else
					.if (bVirtual)
						.if (!bPreClass)
							invoke xprintf, CStr(tab,"%s <>",cr,lf),pszToken
						.endif
					.elseif (bPreClass)
						invoke xprintf, CStr(tab,"%s <>",cr,lf),pszToken
					.endif
					mov bVirtual, FALSE
				.endif
			.endif
			pop ecx
			dec ecx
			inc esi
		.endw
		ret
WriteInherit endp

;--- class tname{};
;--- typedef struct/union tname name;
;--- typedef struct/union <tname> {} name;
;--- typedef struct/union <tname> * name; does not fully work!!! 

ParseTypedefUnionStruct proc pszToken:LPSTR, bIsClass:BOOL

local	pszStruct:LPSTR
local	pszName:LPSTR
local	pszType:LPSTR
local	pszTag:LPSTR
local	pszInherit:LPSTR
local	pszSuffix:LPSTR
local	pszAlignment:LPSTR
local	dwEsp:DWORD
local	bSkipName:BOOLEAN
local	bHasVTable:BOOLEAN
local	bPtr:byte
local	szType[256]:byte
local	szStructName[?MAXSTRUCTNAME]:byte
local	szNoName[64]:byte

		mov dwEsp, esp
		mov eax,pszToken
		mov pszStruct, eax
		mov pszTag, NULL
		mov pszType, NULL
		mov pszName, NULL
		mov pszInherit, NULL
		mov bPtr, 0
		.if (bIsClass)
			mov pszStruct, CStr("struct")
			mov m_bIsClass, TRUE
		.endif
		dprintf <"%u: ParseTypedefUnionStruct '%s'",lf>,m_dwLine, pszStruct
		invoke GetNextToken
		.if (eax && (byte ptr [eax] != '{'))
			dprintf <"%u: ParseTypedefUnionStruct, token '%s' assumed tag",lf>,m_dwLine, eax
			mov pszTag, eax
			mov pszType, eax
			invoke GetNextToken
		.endif
		.if (!eax)
			mov eax,2
			jmp error
		.endif
		.if (byte ptr [eax] == ':')
			.if 0; (!bIsClass)
				invoke printf, CStr("%s, %u: C++ syntax found",lf),
					m_pszFileName, m_dwLine
			.endif
			.while (1)
				invoke GetNextToken
				.if ((!eax) || (byte ptr [eax] == ';'))
					mov eax, 9
					jmp error
				.endif
				.break .if (word ptr [eax] == '{')
				.continue .if (word ptr [eax] == ',')
				mov pszToken, eax
				.if (!pszInherit)
					Create@Stacklist
					mov pszInherit, eax
				.endif
				Add@Stacklist pszInherit, pszToken
			.endw
		.endif
		dprintf <"%u: ParseTypedefUnionStruct, token '%s' found",lf>,m_dwLine, eax
		.if (byte ptr [eax] == '{')
			.if (g_bAddAlign && (!m_bAlignMac))
				invoke write, offset szMac_align
				mov m_bAlignMac, TRUE
			.endif
			mov bHasVTable, FALSE
			.if (bIsClass)
				invoke HasVTable
				mov bHasVTable, al
			.endif
			invoke GetStructName, addr szStructName
			mov bSkipName, TRUE
			.if (!eax)
				mov eax, pszTag
				mov bSkipName, FALSE
			.endif
;----------------------------- no name at all?
			.if (!eax)
				invoke sprintf, addr szNoName, CStr("__H2INCX_STRUCT_%04u"),g_dwStructSuffix
				inc g_dwStructSuffix
				lea eax, szNoName
			.endif
;;			.if (eax)
				lea ecx, szType
				invoke TranslateName, eax, ecx
				mov pszType, eax
				invoke InsertItem, g_pStructures, pszType, 0
				mov pszSuffix, CStr("")
				.if (pszInherit)
					invoke HasVirtualBase, pszInherit
					.if (eax)
;;						mov pszSuffix, CStr("$")
					.endif
				.endif
				invoke GetAlignment, pszType
				.if (eax)
					mov pszAlignment, eax
				.elseif (g_bAddAlign)
					mov pszAlignment, CStr("@align")
				.else
					mov pszAlignment, CStr("")
				.endif
				invoke xprintf, CStr("%s%s",tab,"%s %s",cr,lf),pszType, pszSuffix, pszStruct, pszAlignment
				.if (bHasVTable)
					invoke write, CStr(tab,"DWORD ?",tab,";`vftable'",cr,lf)
				.endif
				.if (pszInherit)
					invoke WriteInherit, pszInherit, TRUE
				.endif
				.if (bIsClass)
					invoke getblock, pszType, DT_STANDARD, pszTag
				.else
					invoke getblock, pszType, DT_STANDARD, NULL
				.endif
				.if (!eax)
					jmp done
				.endif
				.if (pszInherit)
					invoke HasVirtualBase, pszInherit
					.if (eax)
;;						invoke xprintf, CStr("%s",tab,"%s %s",cr,lf),pszType, pszStruct, pszAlignment
;;						  invoke xprintf, CStr(tab,"%s%s <>",cr,lf), pszType, pszSuffix
						invoke WriteInherit, pszInherit, FALSE
;;						invoke xprintf,CStr("%s",tab,"ends",cr,lf), pszType
					.endif
				.endif
				invoke xprintf,CStr("%s%s",tab,"ends",cr,lf), pszType, pszSuffix
				invoke write,CStr(cr,lf)
				.if (bSkipName)
					invoke GetNextToken	;skip structure name
				.endif
				invoke GetNextToken
if 0
			.else
				invoke printf, CStr("%s, %u: %s without name",lf),
					m_pszFileName, m_dwLine, pszStruct
				inc m_dwErrors
				mov eax, 11
				jmp error
			.endif
endif
;-------------------------------------- typedef struct/union tagname typename
		.endif

		.if (eax)
			invoke GetFurtherTypes, pszType, pszTag, eax
		.endif
done:
		xor eax, eax
error:
		mov m_bIsClass, FALSE
		mov esp, dwEsp
		ret
ParseTypedefUnionStruct endp

;--- <typedef> <qualifiers> enum <tname> {x<=a>,y<=b>,...} name<,*name>; 
;--- simplest form is "enum {x = a, y = b};"

ParseTypedefEnum proc bIsTypedef:BOOL

local	pszTag:LPSTR
local	pszName:LPSTR
local	szStructName[?MAXSTRUCTNAME]:byte

		mov pszTag, NULL
		mov pszName, NULL
		invoke GetNextToken
		.if (eax && (byte ptr [eax] != '{'))
			mov pszTag, eax
			invoke GetNextToken
		.endif
		.if (eax && (byte ptr [eax] == '{'))
			.if (bIsTypedef)
				invoke GetStructName, addr szStructName
			.else
				xor eax, eax
			.endif
			.if (!eax)
				mov eax, pszTag
			.endif
			.if (eax)
				mov pszName, eax
				invoke TranslateType, CStr("int"), 0      ;29.8.2022 added
				invoke xprintf, CStr("%s typedef %s",cr,lf), pszName, eax
			.endif
			mov m_dwEnumValue, 0
			invoke getblock, pszName, DT_ENUM, NULL
			invoke write, CStr(cr,lf)
			.if (bIsTypedef)
				invoke GetNextToken	;skip enum name
			.endif
			invoke GetNextToken
			.if (eax && pszName)
				invoke GetFurtherTypes, pszName, NULL, eax
			.endif
		.else
;--- just syntax "typedef enum oldtypename newtypename;
			push eax
			invoke IsName, eax
			pop ecx
			.if (eax)
				invoke write, ecx
				invoke write, CStr(" typedef DWORD",cr,lf)
				xor eax, eax
			.else
				mov eax,2
			.endif
		.endif
error:
		ret
ParseTypedefEnum endp

;--- this gets qualifier string in ECX!

GetCallConvention proc dwQualifiers:DWORD
		mov ecx, dwQualifiers
		and ecx, FQ_STDCALL or FQ_CDECL or FQ_PASCAL or FQ_SYSCALL
		.if (!ecx)
			mov ecx, g_dwDefCallConv
		.endif
		.if (ecx & FQ_STDCALL)
			mov ecx, CStr("stdcall")
		.elseif (ecx & FQ_CDECL)
			mov ecx, CStr("c")
		.elseif (ecx & FQ_PASCAL)
			mov ecx, CStr("pascal")
		.elseif (ecx & FQ_SYSCALL)
			mov ecx, CStr("syscall")
		.else
			mov ecx, CStr("")
		.endif
		ret
GetCallConvention endp

;--- return eax=0 if no proto qualifier

CheckProtoQualifier proc uses esi pszToken:LPSTR

local	sis:INPSTAT
local	bIsDeclSpec:BOOLEAN

		mov bIsDeclSpec, FALSE
		invoke _strcmp, pszToken, CStr("__declspec")
		.if (!eax)
			invoke SaveInputStatus, addr sis
			invoke GetNextToken
			.if (eax && (byte ptr [eax] == '('))
				invoke GetNextToken
				.if (eax)
					mov pszToken, eax
					mov bIsDeclSpec, TRUE
				.endif
			.else
				invoke RestoreInputStatus, addr sis
			.endif
		.endif
if 1
  if ?DYNPROTOQUALS
		invoke FindItem@List, g_pQualifiers, pszToken
  else            
		invoke _bsearch, addr pszToken, g_ProtoQualifiers.pItems,
			g_ProtoQualifiers.numItems, 2*4, cmpproc
  endif            
else
		mov esi, g_ProtoQualifiers
		.while (1)
			lodsd
			.break .if (!eax)
			invoke _strcmp, pszToken, eax
			.if (!eax)
				lea eax, [esi-4]
				.break
			.endif
			add esi, 4
		.endw
endif
done:
		.if (bIsDeclSpec)
			push eax
			invoke GetNextToken
			pop eax
		.endif
		ret
CheckProtoQualifier endp

;--- typedef function pointer
;--- typedef <qualifiers><returntype> ( <qualifiers> * <name> )(<parameters>)
;--- return: eax=0 ok (edx=name), else eax=error code
;--- the first "(" has been read already!
;--- this function has to be reentrant, since a function parameter
;--- may have type "function ptr"

ParseTypedefFunctionPtr proc uses edi pszParent:LPSTR

local	pszToken:LPSTR
local	pszName:LPSTR
local	pszType:LPSTR
local	dwCnt:DWORD
local	dwQualifier:DWORD
local	bPtr:byte
local	szPrototype[768]:byte
local	szType[128]:byte

		mov bPtr, 0
		mov szPrototype, 0
		mov pszName, NULL
		mov dwQualifier, 0
		.while (1)
			invoke GetNextToken
			mov pszToken, eax
			.if (!eax)
				mov eax, 15
				jmp error
			.endif
			.break .if ((byte ptr [eax] == ')') || (byte ptr [eax] == ';'))
			.if (byte ptr [eax] == '*')
				inc bPtr
			.else
				invoke CheckProtoQualifier, eax
				.if (eax)
					mov eax,[eax+4]
					or dwQualifier, eax
				.else
					mov eax, pszToken
					mov pszName, eax	;ignore any qualifiers
				.endif
			.endif
		.endw
;		.if (bPtr && pszName)
;		.if (pszName)
		.if (byte ptr [eax] == ')')
			dprintf <"%u: ParseTypedefFunctionPtr %s",lf>, m_dwLine, pszName
			invoke GetNextToken
			.if (!eax)
				mov eax, 16
				jmp error
			.endif
;--------------------------- get function parameters
			.if (byte ptr [eax] == '(')
				lea edi, szPrototype
				xor eax, eax
				.if (pszName)
					invoke GetCallConvention, dwQualifier
					.if (m_bIsInterface && (dwQualifier & FQ_STDCALL))
						invoke TranslateName, pszName, NULL
						invoke sprintf, edi, CStr("STDMETHOD %s, "), eax
					.elseif (pszParent)
						invoke sprintf, edi, CStr("proto%s_%s typedef proto %s "), pszParent, pszName, ecx
					.else
						invoke sprintf, edi, CStr("proto_%s typedef proto %s "), pszName, ecx
					.endif
				.endif
				add edi, eax
				mov pszType, NULL
				mov bPtr, 0
				mov dwCnt, 0
				.while (1)
					invoke GetNextToken
					.if (!eax || (byte ptr [eax] == ';'))
						mov eax, 11
						jmp error
					.endif
					mov pszToken, eax
					.if ((byte ptr [eax] == ',') || (byte ptr [eax] == ')'))
						push eax
						.if (pszType)
							dprintf <"%u: ParseTypedefFunctionPtr, parameter %s found",lf>, m_dwLine, pszType
							movzx ecx, g_bUntypedParams
							invoke TranslateType, pszType, ecx
							.if (byte ptr [eax])
								mov pszType, eax
							.else
								mov pszType, NULL
							.endif
						.endif
						.if (bPtr || pszType)
							invoke lstrcat, edi, CStr(":")
							.while (bPtr)
								invoke lstrcat, edi, CStr("ptr ")
								dec bPtr
							.endw
							.if (pszType)
								invoke lstrcat, edi, pszType
							.endif
						.endif
						.if ((!dwCnt) && (m_bIsInterface))
							mov byte ptr [edi],0
						.endif
						inc dwCnt
						pop eax
						.break .if (byte ptr [eax] == ')')
						invoke lstrcat, edi, CStr(",")
						.if ((dwCnt == 1) && (m_bIsInterface))
							mov byte ptr [edi],0
						.endif
						mov pszType, NULL
						mov bPtr, 0
						.continue
					.endif
					.if (byte ptr [eax] == '*')
						inc bPtr
						.continue
					.elseif (byte ptr [eax] == '[')
						inc bPtr
						.while (1)
							invoke GetNextToken
							.break .if ((!eax) || (word ptr [eax] == ']') || (word ptr [eax] == ';'))
						.endw
						.continue
					.elseif (byte ptr [eax] == '(')
;------------------------------------- function ptr as function parameter?
						invoke IsFunctionPtr
						.if (eax)
							movzx eax, m_bIsInterface
							push eax
							mov m_bIsInterface, FALSE
							invoke ParseTypedefFunctionPtr, pszName
							pop eax
							mov m_bIsInterface, al
							invoke sprintf, addr szType, CStr("p%s_%s"), pszName, edx
							lea eax, szType
							mov pszType, eax
						.endif
						.continue
					.endif
					invoke _strcmp, pszToken, CStr("struct")
					.continue .if (!eax)
					invoke ConvertTypeQualifier, pszToken
					.continue .if (byte ptr [eax] == 0)
					.if (!pszType)
						mov eax, pszToken
						mov pszType, eax
					.endif
				.endw
				.if (pszName)
					invoke write, addr szPrototype
					invoke write, CStr(cr,lf)
					.if (m_bIsInterface)
					.else
						.if (pszParent)
							invoke xprintf, CStr("p%s_%s"), pszParent, pszName
						.else
							invoke TranslateName, pszName, NULL
							invoke xprintf, CStr("%s"), eax
						.endif
						invoke write, CStr(" typedef ")
						.if (pszParent)
							invoke xprintf, CStr("ptr proto%s_%s",cr,lf), pszParent, pszName
						.else
							invoke xprintf, CStr("ptr proto_%s",cr,lf), pszName
						.endif
					.endif
				.endif
if 0
;------------------------ may be an inline function!
				.if (bAcceptBody)
					invoke PeekNextToken
					.if (eax && (word ptr [eax] == '{'))
						invoke GetNextToken
						mov dwCnt, 1
						.while (dwCnt)
							invoke GetNextToken
							.break .if (!eax)
							.if (word ptr [eax] == '{')
								inc dwCnt
							.elseif (word ptr [eax] == '}')
								dec dwCnt
							.endif
						.endw
					.endif
				.endif
endif
			.else
				mov eax, 17
				dprintf <"%u: ParseTypedefFunctionPtr error %u",lf>, m_dwLine, eax
				jmp error
			.endif
		.else
			mov eax, 18
			dprintf <"%u: ParseTypedefFunctionPtr error %u",lf>, m_dwLine, eax
			jmp error
		.endif
		mov edx, pszName
		xor eax, eax
error:
		ret
ParseTypedefFunctionPtr endp

;--- + typedef <qualifiers> returntype name(<parameters>)<{...}>;
;--- or in a class definition:
;--- + <qualifiers> returntype name(<parameters>)<{...}>;

ParseTypedefFunction proc pszName:LPSTR, bAcceptBody:DWORD, pszParent:LPSTR

local	pszToken:LPSTR
local	pszType:LPSTR
local	dwCnt:DWORD
local	dwNum:DWORD
local	cCallConv:DWORD
local	dwEsp:DWORD
local	bPtr:byte
local	bFirstParam:BOOLEAN
local	pszDecoName:LPSTR
local	szFuncName[32]:byte

		mov dwEsp, esp
		mov bFirstParam, FALSE
		.if (m_bIsClass)
			invoke lstrlen, pszParent
			shl eax, 1
			add eax, 64
			and al,0FCh
			sub esp, eax
			mov pszDecoName, esp
			mov dwNum, 0
			mov eax, pszName
			.if (byte ptr [eax] == '~')
				inc eax
				inc dwNum
			.endif
			invoke _strcmp, eax, pszParent
			.if (!eax)
				invoke sprintf, addr szFuncName, CStr("?%u"), dwNum
				lea eax, szFuncName
				mov pszName, eax
			.endif
			mov cCallConv, 'A'	;A=cdecl,G=stdcall
			invoke sprintf, pszDecoName, CStr("?%s@%s@@Q%c___Z"),
				pszName, pszParent, cCallConv
			invoke xprintf, CStr(";externdef syscall %s:near",cr,lf), pszDecoName
			invoke xprintf, CStr(";%s proto :ptr %s"), pszDecoName, pszParent
			mov bFirstParam, TRUE
		.else
			invoke xprintf, CStr("%s typedef proto stdcall "), pszName
		.endif
		mov pszType, NULL
		mov bPtr, 0
		.while (1)
			invoke GetNextToken
			.if (!eax)
				mov eax, 11
				jmp error
			.endif
			.if ((byte ptr [eax] == ',') || (byte ptr [eax] == ')'))
				push eax
				.if (bPtr || pszType)
					.if (pszType)
						movzx ecx, g_bUntypedParams
						invoke TranslateType, pszType, ecx
						mov pszType, eax
					.endif
					mov eax, pszType
					.if ((bPtr) || (byte ptr [eax]))
						.if (bFirstParam)
							invoke write, CStr(",")
							mov bFirstParam, FALSE
						.endif
						invoke write, CStr(":")
					.endif
					.while (bPtr)
						invoke write, CStr("ptr ")
						dec bPtr
					.endw
					.if (pszType)
						invoke write, pszType
					.endif
				.endif
				pop eax
				.break .if (byte ptr [eax] == ')')
				invoke write, CStr(",")
				mov pszType, NULL
				mov bPtr, 0
				.continue
			.endif
			.if (byte ptr [eax] == '*')
				inc bPtr
				.continue
			.endif
			mov pszToken, eax
			invoke _strcmp, pszToken, CStr("struct")
			.continue .if (!eax)
			invoke ConvertTypeQualifier, pszToken
			.continue .if (byte ptr [eax] == 0)
			.if (!pszType)
				mov eax, pszToken
				mov pszType, eax
			.endif
		.endw
		invoke write, CStr(cr,lf)
		.if (bAcceptBody)
			invoke PeekNextToken
			.if (eax && (word ptr [eax] == '{'))
				invoke GetNextToken
				mov dwCnt, 1
				.while (dwCnt)
					invoke GetNextToken
					.break .if (!eax)
					.if (word ptr [eax] == '{')
						inc dwCnt
					.elseif (word ptr [eax] == '}')
						dec dwCnt
					 .endif
				.endw
			.endif
		.endif
		xor eax, eax
error:
		mov esp, dwEsp
		ret
ParseTypedefFunction endp

;--- typedef occured
;--- syntax:
;--- + typedef <qualifiers> type <<far|near> *> newname<[]>;
;--- + typedef struct/union <tname> {} name;
;--- + typedef struct/union <tname> * name; does not work!!! 
;--- + typedef <qualifiers> enum <tname> {x<=a>,y<=b>,...} name; 
;--- + typedef <qualifiers> returntype (<qualifiers> *name)(<parameters>);
;--- + typedef <qualifiers> returntype name(<parameters>);
;--- esi -> tokens behind "typedef"

ParseTypedef proc

local	pszName:LPSTR
local	pszToken:LPSTR
local	pszType:LPSTR
local	pszDup:LPSTR
local	dwCntBrace:dword
local	dwSquareBraces:dword
local	bPtr:byte
local	bValid:BOOLEAN
local	bUnsigned:BOOLEAN
local	sis:INPSTAT
local	szTmpType[64]:byte
local	szType[256]:byte

		dprintf <"%u: ParseTypedef begin",lf>, m_dwLine
		mov bUnsigned, FALSE
nexttoken:
		invoke GetNextToken
		.if (eax)
			invoke TranslateToken, eax
		.endif
		mov pszToken, eax
		.if (!eax || (byte ptr [eax] == ';'))
			mov eax, 1
			jmp error
		.endif
		.if (byte ptr [eax] == '[')
			dprintf <"%u: ParseTypedef: '[' found",lf>, m_dwLine
			invoke SaveInputStatus, addr sis
			invoke GetNextToken
			.if (eax)
				invoke _strcmp, eax, CStr("public")
				.if (!eax)
					invoke GetNextToken
					.if (eax && byte ptr [eax] == ']')
						dprintf <"%u: ParseTypedef: ']' found",lf>, m_dwLine
						jmp nexttoken
					.endif
				.endif
			.endif
			invoke RestoreInputStatus, addr sis
		.endif

		invoke lstrcmpi, pszToken, CStr("const")
		.if (!eax)
			jmp nexttoken
		.endif

;-------------------------------------- syntax: "typedef <macro()> xxx"
		invoke IsMacro, pszToken
		.if (eax)
			dprintf <"%u: ParseTypedef, macro invocation %s",lf>, m_dwLine, pszToken
			invoke MacroInvocation, pszToken, eax, TRUE
			.if (eax)
				jmp nexttoken
			.endif
		.endif

;-------------------------------------- syntax: "typedef union|struct"?
		invoke IsUnionStructClass, pszToken
		.if (eax)
			dprintf <"%u: ParseTypedef, '%s' found",lf>, m_dwLine, pszToken
			invoke ParseTypedefUnionStruct, pszToken, edx
			jmp @exit
		.endif
;-------------------------------------- syntax: "typedef enum"?
		invoke lstrcmpi, pszToken, CStr("enum")
		.if (!eax)
			dprintf <"%u: ParseTypedef, 'enum' found",lf>, m_dwLine
			invoke ParseTypedefEnum, TRUE
			jmp @exit
		.endif
;-------------------------------------- pszToken may be OLD TYPE

		invoke _strcmp, pszToken, CStr("unsigned")
		.if (!eax)
			mov bUnsigned, TRUE
			jmp nexttoken
		.endif
		invoke _strcmp, pszToken, CStr("signed")
		.if (!eax)
			mov bUnsigned, FALSE
			jmp nexttoken
		.endif

if 0
			invoke lstrcpy, addr szTmpType, pszToken
			invoke lstrcat, addr szTmpType, CStr(" ")
			invoke GetNextToken
			.if (!eax || (byte ptr [eax] == ';'))
				mov eax, 7
				jmp error
			.endif
			invoke lstrcat, addr szTmpType, eax
			lea eax,szTmpType
			mov pszToken, eax
		.endif
endif
		.if (bUnsigned)
			movzx ecx, bUnsigned
			xor edx, edx
			invoke MakeType, pszToken, ecx, edx, addr szType
			mov pszToken, eax
		.endif

		invoke TranslateType, pszToken, 0
		mov pszType, eax
		mov bPtr, 0
		mov pszName, NULL
		mov pszDup, NULL
		mov dwSquareBraces,0
		.while (1)
			invoke GetNextToken
			.if (!eax)
				mov eax, 2
				jmp error
			.endif
			.if ((byte ptr [eax] == ',') || (byte ptr [eax] == ';'))
				push eax
				.if (pszName)
					mov bValid, TRUE
;---- dont add "<newname> typedef <oldname>" entries if <newname> == <oldname>
					.if (!bPtr)
						invoke _strcmp, pszName, pszType
						.if (!eax)
							invoke write, CStr(";")
							mov bValid, FALSE
						.endif
					.endif
					.if (bValid)
						invoke TranslateName, pszName, addr szType
						push eax
						.if (edx && (g_bWarningLevel > 0))
							invoke printf, CStr("%s, %u: reserved word '%s' used as typedef",lf),
								m_pszFileName, m_dwLine, pszName
							inc m_dwWarnings
						.endif
						pop pszName
					.endif
					dprintf <"%u: new typedef %s=%s",lf>,m_dwLine, pszName, pszType
					; if there is an array index, create a struct instead of a typedef!
					.if ( pszDup && (bPtr == NULL))
						invoke write, pszName
						invoke write, CStr(" struct", cr,lf)
						invoke write, CStr(tab)
						invoke write, pszType
						invoke write, CStr(" ")
						invoke write, pszDup
						invoke write, CStr(" dup (?)", cr,lf)
						invoke write, pszName
						invoke write, CStr(" ends", cr,lf)
					.else
						invoke write, pszName
						invoke write, CStr(" typedef ")
						push esi
						movzx esi, bPtr
						.while (esi)
							invoke write, CStr("ptr ")
							dec esi
						.endw
						pop esi
						invoke write, pszType
						invoke write, CStr(cr,lf)
					.endif
;---------------------------- add type to structure table if necessary					  
					.if (bValid && (!bPtr))
						invoke IsStructure, pszType
						.if (eax)
							invoke InsertItem, g_pStructures, pszName, 0
						.endif
					.endif
if ?TYPEDEFSUMMARY
					.if (g_bTypedefSummary && bValid)
						invoke InsertItem, g_pTypedefs, pszName, 0
					.endif
endif
				.endif
				mov bPtr, 0
				mov pszName, NULL
				pop eax
				.break .if (byte ptr [eax] == ';')
			.endif
			.if (byte ptr [eax] == '(')
				invoke IsFunctionPtr
				.if (eax)
					invoke ParseTypedefFunctionPtr, NULL
				.else
					mov eax, pszName
					.if (!eax)
						mov eax, pszType
					.endif
					invoke ParseTypedefFunction, eax, FALSE, NULL
				.endif
				mov pszName, NULL
				.if (eax)
					jmp @exit
				.endif
			.elseif (byte ptr [eax] == '*' && dwSquareBraces == 0 )
				inc bPtr
			.elseif (byte ptr [eax] == '[')
				dprintf <"%u: ParseTypedef, '[' found",lf>, m_dwLine
				inc dwSquareBraces
			.elseif (byte ptr [eax] == ']')
				dprintf <"%u: ParseTypedef, ']' found",lf>, m_dwLine
				dec dwSquareBraces
			.else
				.if (dwSquareBraces)
					.if ( pszDup )
						push eax
						invoke lstrlen, eax
						push eax
						invoke lstrlen, pszDup
						pop ecx
						add eax,ecx
						inc eax
						inc eax
						invoke malloc, eax
						push ebx
						mov ebx, eax
						invoke lstrcpy, ebx, pszDup
						invoke free, pszDup
						mov pszDup, ebx
						invoke lstrcat, ebx, CStr(" ")
						invoke lstrcat, ebx, [esp+4]
						pop ebx
						pop eax
					.else
						mov pszDup, eax
					.endif
					dprintf <"%u: ParseTypedef, array size '%s' found",lf>, m_dwLine, eax
					.continue
				.endif
				invoke ConvertTypeQualifier, eax
				.continue.if (byte ptr [eax] == 0)
				mov pszToken, eax
				invoke IsName, eax
				.if (eax)
					mov eax, pszToken
					mov pszName, eax
				.endif
			.endif
		.endw
		xor eax, eax
@exit:
error:
		.if (eax)
			invoke printf, CStr("%s, %u: unexpected item %s in typedef [%u]",lf),
				m_pszFileName, m_dwLine, pszToken, eax
			inc m_dwErrors
		.endif
		dprintf <"%u: ParseTypedef end",lf>, m_dwLine
		ret
ParseTypedef endp

if 0
CheckApiType proc uses esi pszToken:ptr byte
		mov esi, g_pFirstApi
		.while (esi)
			lea eax, [esi+4]
			invoke _strcmp, pszToken, eax
			.if (!eax)
				jmp istrue
			.endif
			mov esi,[esi]
		.endw
		xor eax,eax
		ret
istrue:
		mov eax,1
		ret
CheckApiType endp
endif

ParseExtern proc

local	pszToken:LPSTR

		.while (1)
			invoke GetNextToken
			mov pszToken, eax
			.break .if (!eax)
			.break .if (byte ptr [eax] == ';')
if ?ADDTERMNULL
			.if ((dword ptr [eax] == ',"C"') && (word ptr [eax+4] == '0'))
else
			.if (dword ptr [eax] == '"C"')
endif
				invoke write, CStr(";extern ",22h,"C",22h,cr,lf)
				mov m_bC, TRUE
				.break
if ?ADDTERMNULL
			.elseif ((dword ptr [eax] == '++C"') && (dword ptr [eax+4] == '0,"'))
else
			.elseif ((dword ptr [eax] == '++C"') && (word ptr [eax+4] == '"'))
endif
				invoke write, CStr(";extern ",22h,"C++",22h,cr,lf)
				.break
			.endif
			invoke write, CStr("externdef ")
			.if (m_bC)
				invoke write, CStr("c ")
			.endif
			invoke GetDeclaration, pszToken, NULL, DT_EXTERN
			.break
		.endw
		ret
ParseExtern endp

TranslateName2 proc pszFuncName:LPSTR            
		invoke TranslateName, pszFuncName, NULL
		.if (edx && (g_bWarningLevel > 0))
			push eax
			invoke printf, CStr("%s, %u: reserved word '%s' used as prototype",lf),
				m_pszFileName, m_dwLine, pszFuncName
			pop eax
			inc m_dwWarnings
		.endif
		ret
TranslateName2 endp            

;--- parse a function prototype

ParsePrototype proc pszFuncName:LPSTR, pszImpSpec:LPSTR, pszCallConv:LPSTR				 

local	bUnsigned:BYTE
local	dwPtr:DWORD
local	dwCnt:DWORD
local	dwParmBytes:DWORD
local	bFunctionPtr:BOOLEAN
local	pszType:LPSTR
local	pszName:LPSTR
local	pszToken:LPSTR
local	pszPrefix:LPSTR
local	sis:INPSTAT
local	szSuffix[8]:byte
local	szType[512]:byte

		dprintf <"%u: ParsePrototype name=%s, pszImpSpec=%X",lf>, m_dwLine, pszFuncName, pszImpSpec
		.if (g_bUseDefProto && pszImpSpec)
		.else
			.if (g_bAssumeDllImport)
				or m_dwQualifiers, FQ_IMPORT
			.elseif (g_bIgnoreDllImport)
				and m_dwQualifiers, not FQ_IMPORT
			.endif
		.endif
		invoke GetCallConvention, m_dwQualifiers
		.if (g_bUseDefProto && pszImpSpec)
			.if 0;(pszCallConv)
				mov ecx, pszCallConv
			.endif
			push ecx
			invoke IsReservedWord, pszFuncName
			.if (eax)
				invoke printf, CStr("%s, %u: reserved word '%s' used as prototype",lf),
					m_pszFileName, m_dwLine, pszFuncName
				inc m_dwWarnings
				mov eax,CStr("_")
			.else
				mov eax,CStr("")
			.endif
			pop ecx
			invoke xprintf, CStr("@DefProto %s, %s, %s, %s, ",3Ch), pszImpSpec, pszFuncName, ecx, eax
		.elseif (m_dwQualifiers & FQ_IMPORT)
			invoke xprintf, CStr("proto_%s typedef proto %s "), pszFuncName, ecx
		.else
			push ecx
			invoke TranslateName2, pszFuncName
			pop ecx
			invoke xprintf, CStr("%s proto %s "), eax, ecx
		.endif
		mov m_pszLastToken, NULL
		mov pszType, NULL
		mov pszName, NULL
		mov bFunctionPtr, FALSE
		mov dwPtr, 0
		mov dwParmBytes,0
		mov dwCnt, 1
		mov bUnsigned, FALSE
		.while (dwCnt)
			invoke GetNextToken
			.break .if (!eax)
			.break .if (byte ptr [eax] == ';')
			.if ((byte ptr [eax] == ',') || (byte ptr [eax] == ')'))
				push eax
				.if (pszName || dwPtr || bUnsigned)
					.if (!pszType)
						mov eax, pszName
						mov pszType, eax
						mov pszName, NULL
					.endif
					mov eax, pszType
					.if (dwPtr && (!eax))
						mov eax, CStr("")	;make sure its a valid LPSTR
					.else
						movzx ecx, bUnsigned
						mov edx, 0
						invoke MakeType, pszType, ecx, edx, addr szType
						mov pszType, eax
						movzx ecx, g_bUntypedParams
						invoke TranslateType, pszType, ecx
						mov pszType, eax
					.endif
;--- dont interpret xxx(void) as parameter
					.if ((!dwPtr) && (byte ptr [eax] == 0))
						;
					.else
						.if (dwParmBytes)
							invoke write, CStr(" :")
						.else
							invoke write, CStr(":")
						.endif
						.if (dwPtr)
							mov eax, 4
						.else
							invoke GetTypeSize, pszType
						.endif
						add dwParmBytes, eax
					.endif
					.while (dwPtr)
						invoke write, CStr("ptr ")
						dec dwPtr
					.endw
					.if (pszType)
						invoke write, pszType
					.endif
					mov pszType, NULL
					mov pszName, NULL
					mov bFunctionPtr, FALSE
					mov bUnsigned, FALSE
				.endif
				pop eax
				.if (byte ptr [eax] == ')')
					dec dwCnt
				.else
					invoke write, eax
				.endif
			.elseif ((byte ptr [eax] == '*') || (byte ptr [eax] == '&'))
				inc dwPtr
			.elseif (word ptr [eax] == '[')
				inc dwPtr
				.while (1)
					invoke GetNextToken
					.break .if ((!eax) || (word ptr [eax] == ']') || (word ptr [eax] == ';'))
				.endw
			.elseif (byte ptr [eax] == '(')
;------------------------------------- function ptr as function parameter?
				invoke IsFunctionPtr
				.if (eax)
					push m_pszOut
					invoke ParseTypedefFunctionPtr, NULL
					pop m_pszOut
;;					invoke sprintf, addr szType, CStr("p%s_%s"), pszName, edx
					mov dwPtr, 1
					mov pszName, NULL
				.else
					inc dwCnt
				.endif
			.else
				mov pszToken, eax
				invoke ConvertTypeQualifier, pszToken
				.continue .if (byte ptr [eax] == 0)
				invoke _strcmp, pszToken, CStr("struct")
				.continue .if (!eax)
				invoke _strcmp, pszToken, CStr("unsigned")
				.if (!eax)
					mov bUnsigned, TRUE
					.continue
				.endif
				invoke _strcmp, pszToken, CStr("...")
				.if (!eax)
					mov pszToken, CStr("VARARG")
				.endif
				mov ecx, pszName
				mov pszType, ecx
				mov eax, pszToken
				mov pszName, eax
			.endif
		.endw
		.if (g_bUseDefProto && pszImpSpec)
			invoke write, CStr(3Eh)
			and m_dwQualifiers, not FQ_IMPORT
			.if (m_dwQualifiers & FQ_STDCALL)
				invoke xprintf, CStr(", %u"), dwParmBytes
			.endif
		.endif
		invoke write, CStr(cr,lf)
		
		.if (m_dwQualifiers & FQ_IMPORT)
if 1
			.if (m_dwQualifiers & FQ_STDCALL)
				mov pszPrefix, CStr("_")
				invoke sprintf, addr szSuffix, CStr("@%u"), dwParmBytes
			.elseif (m_dwQualifiers & FQ_CDECL)
				mov pszPrefix, CStr("_")
				mov szSuffix, 0
			.else
				mov pszPrefix, CStr("")
				mov szSuffix, 0
			.endif
endif
			invoke xprintf, CStr("externdef stdcall _imp_%s%s%s: ptr proto_%s",cr,lf),
				pszPrefix, pszFuncName, addr szSuffix, pszFuncName
			invoke TranslateName2, pszFuncName
			mov ecx, eax
			invoke xprintf, CStr("%s equ ",3Ch,"_imp_%s%s%s",3Eh,cr,lf),
				ecx, pszPrefix, pszFuncName, addr szSuffix
		.endif
if ?PROTOSUMMARY
		.if (g_bProtoSummary)
			invoke InsertItem, g_pPrototypes, pszFuncName, 0
		.endif
endif		 
		.if (g_bCreateDefs)
			invoke InsertDefItem, pszFuncName, dwParmBytes
		.endif
		.if (m_dwQualifiers & FQ_INLINE)
			invoke SaveInputStatus, addr sis
			invoke GetNextToken
			.if (eax && (byte ptr [eax] == '{'))
				mov dwCnt, 1
				.while (dwCnt)
					invoke GetNextToken
					.break .if (!eax)
					.if (byte ptr [eax] == '{')
						inc dwCnt
					.elseif (byte ptr [eax] == '}')
						dec dwCnt
					.endif
				.endw
			.else
				invoke RestoreInputStatus, addr sis
			.endif
		.endif
@exit:
		ret
ParsePrototype endp

;--- a known macro has been found
;--- if bit 0 of pNameItem is set then it is a macro from h2incx.ini
;--- returns 1 if macro was invoked
;--- else 0 (turned out to be NO macro invocation)

MacroInvocation proc pszToken:LPSTR, pNameItem:ptr NAMEITEM, bWriteLF:DWORD

local	dwCnt:DWORD
local	dwParms:DWORD		;parameters for macro
local	dwFlags:DWORD		;flags from h2incx.ini
local	pszType:LPSTR
local	pszName:LPSTR
local	bPtr:BYTE
local	pszOutSave:LPSTR

		mov ecx, pNameItem
		test cl,1
		.if (ZERO?)
			push [ecx].NAMEITEM.pszName
			invoke lstrlen, [ecx].NAMEITEM.pszName
			pop ecx
			mov eax, [ecx+eax+1]	;number of parameters
			mov dwParms, eax
			mov dwFlags, 0
		.else
			mov dwParms, 0
			mov dwFlags, ecx
		.endif

		mov eax, m_pszOut
		mov pszOutSave, eax

		dprintf <"%u: macro invocation found: %s",lf>, m_dwLine, pszToken
		.if (dwFlags & MF_INTERFACEEND)
			invoke xprintf, CStr("??Interface equ <>",13,10)
			mov m_bIsInterface, FALSE
		.endif
		invoke PeekNextToken
		.if (eax && (byte ptr [eax] == '('))
			invoke write, pszToken
			invoke GetNextToken
			.if (!(dwFlags & MF_SKIPBRACES))
				invoke write, eax
			.else
				invoke write, CStr(" ")
			.endif
			mov dwCnt, 1
			.while (1)
				invoke GetNextToken
				.break .if (!eax)
				.if (byte ptr [eax] == ')')
					dec dwCnt
				.elseif (byte ptr [eax] == '(')
					inc dwCnt
				.endif
				.break .if (!dwCnt)
				.if (dwFlags & MF_PARAMS)
					invoke TranslateName, eax, NULL
				.endif
				dprintf <"%u: macro parameter: %s",lf>, m_dwLine, eax
				push eax
				mov al,[eax]
				call IsAlpha
				.if (eax)
					invoke write, CStr(" ")
				.endif
				pop eax
				invoke TranslateOperator, eax
				invoke write, eax
			.endw
			.if (!(dwFlags & MF_SKIPBRACES))
				invoke write, CStr(29h)
			.else
				invoke write, CStr(" ")
			.endif
			.if (dwFlags & MF_COPYLINE)
				mov bPtr, 0
				mov pszName, NULL
				mov pszType, NULL
				.while (1)
					.if (dwFlags & MF_PARAMS)
						invoke GetNextToken
						.break .if ((!eax) || (word ptr [eax] == ';'))
					.else
						invoke GetNextTokenPP
						.break .if (!eax)
					.endif
					.if (dwFlags & MF_PARAMS)
						.if ((word ptr [eax] == ')') || (word ptr [eax] == ','))
							push eax
							mov eax, pszType
							.if (!eax)
								mov eax, pszName
							.endif
							.if (eax)
								dprintf <"%u: MacroInvocation, param=%s",lf>,m_dwLine,eax
								push eax
								invoke write, CStr(", :")
								.while (bPtr)
									invoke write, CStr("ptr ")
									dec bPtr
								.endw
								pop eax
								movzx ecx, g_bUntypedParams
								invoke TranslateType, eax, ecx
								invoke write, eax
							.endif
							mov pszType, NULL
							mov pszName, NULL
							mov bPtr, 0
							pop eax
							.continue .if (word ptr [eax] == ',')
						.endif
						.if (word ptr [eax] == '(')
							inc dwCnt
						.elseif (word ptr [eax] == ')')
							dec dwCnt
						.elseif (word ptr [eax] == '*')
							inc bPtr
						.elseif (word ptr [eax] == '[')
							inc bPtr
							.while (1)
								invoke GetNextTokenPP
								.break .if ((!eax) || (word ptr [eax] == ']'))
							.endw
						.else
							mov ecx, [eax]
							or ecx, 20202020h
							.if (ecx == "siht")
								mov cx,[eax+4]
								.if ((cl == 0) || ((cl == '_') && (ch == 0)))
									.continue
								.endif
							.endif
							invoke ConvertTypeQualifier, eax
							.if (byte ptr [eax])
								xchg eax, pszName
								mov pszType, eax
							.endif
						.endif
						.continue
					.endif
					invoke write, eax
				.endw
			.endif	;(dwFlags & MF_COPYLINE)
		.else
			.if (!dwParms)
				invoke write, pszToken
			.else
				xor eax, eax
				jmp @exit
			.endif
		.endif
		.if (dwFlags & MF_ENDMACRO)
			mov eax, pszToken
			mov m_pszEndMacro, eax
			mov eax, m_dwBraces
			mov m_dwBlockLevel, eax
		.endif
done:
		.if (bWriteLF)
			invoke write, CStr(cr,lf)
		.endif
		.if ((dwFlags & MF_INTERFACEBEG) && (m_pszStructName))
			invoke xprintf, CStr("??Interface equ <%s>",13,10), m_pszStructName
			mov m_bIsInterface, TRUE
		.endif
		.if (!g_bConstants)
			mov ecx, pszOutSave
			mov m_pszOut, ecx
			mov byte ptr [ecx],0
		.endif
		.if (dwFlags & MF_STRUCTBEG)
			invoke ParseTypedefUnionStruct, CStr("struct"), FALSE
		.endif
		mov eax, 1
@exit:
		ret
MacroInvocation endp

;--- the following types of declarations are known:
;--- 1. typedef (struct, enum)
;--- 2. extern
;--- 3. prototypes 

ParseC proc

local	bNextParm:BOOLEAN
local	bIsClass:BOOLEAN
local	pszToken:LPSTR

		invoke GetNextToken
		.if (!eax)
			dprintf <"%u: ParseC, eof reached",lf>, m_dwLine
			ret
		.endif
		push eax
		invoke WriteComment
		.if (eax)
			invoke write, CStr(cr,lf)
		.endif
		pop eax
		.if (byte ptr [eax] == ';')
			mov m_pszLastToken, NULL
			mov m_pszImpSpec, NULL
			mov m_pszCallConv, NULL
			mov m_dwQualifiers, 0
			jmp @exit
		.endif
if 1
		invoke TranslateToken, eax
endif
		mov pszToken, eax
		invoke _strcmp, eax, CStr("typedef")
		.if (!eax)
			push m_pszOut
			dprintf <"%u: ParseC, 'typedef' found",lf>, m_dwLine
			invoke ParseTypedef
			pop ecx
			.if (!g_bTypedefs)
				mov m_pszOut, ecx
				mov byte ptr [ecx],0
			.endif
			jmp @exit
		.endif
;--- "struct" may be a struct declaration, but may be a function returning 
;--- a struct as well. Hard to tell.
;--- even more, it may be just a forward declaration! ignore that!
		invoke IsUnionStructClass, pszToken
		.if (eax)
			dprintf <"%u: ParseC, 'union/struct/class' found",lf>, m_dwLine
			push edx
			invoke IsFunction
			pop edx
			.if (!eax)
				push m_pszOut
				invoke ParseTypedefUnionStruct, pszToken, edx
				pop ecx
				.if (!g_bTypedefs)
					mov m_pszOut, ecx
					mov byte ptr [ecx],0
				.endif
				jmp @exit
			.endif
			dprintf <"%u: ParseC, 'union/struct' ignored (function return type)",lf>, m_dwLine
		.endif
		invoke _strcmp, pszToken, CStr("extern")
		.if (!eax)
			invoke IsFunction
			.if (!eax)
				push m_pszOut
				dprintf <"%u: ParseC, 'extern' found",lf>, m_dwLine
				invoke ParseExtern
				pop ecx
				.if (!g_bExternals)
					mov m_pszOut, ecx
					mov byte ptr [ecx],0
				.endif
			.endif
			jmp @exit
		.endif
		invoke _strcmp, pszToken, CStr("enum")
		.if (!eax)
			dprintf <"%u: ParseC, 'enum' found",lf>, m_dwLine
			invoke ParseTypedefEnum, FALSE
			jmp @exit
		.endif

;--- first check if name is a known prototype qualifier
;--- this may also be a macro, but no macro invocation should
;--- be generated then

		invoke CheckProtoQualifier, pszToken
		.if (eax)
			mov ecx,[eax+4]
			dprintf <"%u: ParseC, prototype qualifier '%s' found, value=%X",lf>, m_dwLine, pszToken, ecx
;--- changed v0.99.21
;			.if (ecx == FQ_IMPORT)
			.if (ecx & FQ_IMPORT)
				mov eax, pszToken
				mov m_pszImpSpec, eax
			.elseif ((ecx == FQ_STDCALL) || (ecx == FQ_CDECL) || (ecx == FQ_SYSCALL) || (ecx == FQ_PASCAL))
				mov eax, pszToken
				mov m_pszCallConv, eax
			.endif
			or m_dwQualifiers, ecx
			jmp @exit
		.endif
		.if (!m_dwQualifiers)
			invoke IsMacro, pszToken
			.if (eax)
				invoke MacroInvocation, pszToken, eax, TRUE
				.if (eax)
					jmp @exit
				.endif
			.endif
		.endif

		mov eax, pszToken
		.if (byte ptr [eax] == '(')
			.if (m_pszLastToken)
				dprintf <"%u: ParseC, prototype found",lf>, m_dwLine
				push m_pszOut
				invoke ParsePrototype, m_pszLastToken, m_pszImpSpec, m_pszCallConv
				pop ecx
				.if (!g_bPrototypes)
					mov m_pszOut, ecx
					mov byte ptr [ecx],0
				.endif
				jmp @exit
			.endif
		.endif

		invoke IsName, pszToken
		.if (eax)
			mov eax, pszToken
			mov m_pszLastToken, eax
			dprintf <"%u: token %s found",lf>, m_dwLine, eax
		.else
			mov eax, pszToken
			.if (word ptr [eax] == '{')
				inc m_dwBraces
				mov eax,m_pszOut
				.if (byte ptr [eax-1] == lf)
					invoke write, CStr(";{",cr,lf)
				.endif
				dprintf <"%u: begin block, new level=%u",lf>, m_dwLine, m_dwBraces
			.elseif (word ptr [eax] == '}')
				dec m_dwBraces
				mov eax,m_pszOut
				.if (byte ptr [eax-1] == lf)
					invoke write, CStr(";}",cr,lf)
				.endif
				dprintf <"%u: end block, new level=%u",lf>, m_dwLine, m_dwBraces
				mov eax, m_dwBraces
				.if ((m_pszEndMacro) && (eax == m_dwBlockLevel))
					invoke xprintf, CStr("%s_END",cr,lf,cr,lf), m_pszEndMacro
					mov m_dwBlockLevel, 0
					mov m_pszEndMacro, NULL
				.endif
			.endif
		.endif

@exit:
		.if (g_bIncludeComments && (g_szComment+1))
			invoke write, addr g_szComment
			mov g_szComment+1,0
			invoke write, CStr(cr,lf)
		.endif
		mov eax, 1
		ret
ParseC endp

;---------------------------------------------------

Analyzer@IncFile proc public uses esi edi _this pThis:ptr INCFILE

local	_st:SYSTEMTIME

		mov _this, pThis
		dprintf <"Analyzer@IncFile begin %s",lf>, m_pszFileName
		mov edi, m_pBuffer2
		mov m_pszIn, edi
ifdef _DEBUG
		invoke _lcreat, CStr(".\~parser.tmp"), 0
		.if (eax != -1)
			mov esi, eax
			mov ecx, m_pszOut
			sub ecx, edi
			invoke _lwrite, esi, edi, ecx
			invoke _lclose, esi
		.endif
endif
		mov edi, m_pBuffer1
		mov byte ptr [edi],0
		mov m_pszOut, edi
		mov m_bComment, 0
		mov m_bDefinedMac, FALSE
		mov m_bAlignMac, FALSE
		mov m_bSkipPP, 0
		mov m_dwLine, 1
		mov m_bNewLine, TRUE

		.if (!g_pStructures)
			invoke Create@List, ?MAXITEMS, 4
			mov g_pStructures, eax
;;			invoke AddItemArray@List, eax, g_KnownStructures.pItems, g_KnownStructures.numItems
		.endif
		.if (!g_pMacros)
			invoke Create@List, ?MAXITEMS, 4
			mov g_pMacros, eax
		.endif
if ?PROTOSUMMARY
		.if (g_bProtoSummary && (!g_pPrototypes))
			invoke Create@List, ?MAXITEMS, 4
			mov g_pPrototypes, eax
		.endif
endif
if ?TYPEDEFSUMMARY
		.if (g_bTypedefSummary && (!g_pTypedefs))
			invoke Create@List, ?MAXITEMS, 4
			mov g_pTypedefs, eax
		.endif
endif
if ?DYNPROTOQUALS
		.if (!g_pQualifiers)
			invoke Create@List, 400h, 2*4
			mov g_pQualifiers, eax
			invoke AddItemArray@List, eax, g_ProtoQualifiers.pItems, g_ProtoQualifiers.numItems
		.endif
endif
		.if (g_bCreateDefs)
			invoke Create@List, ?MAXITEMS, 4
			mov m_pDefs, eax
		.endif

		invoke write, CStr(";--- include file created by h2incx ",?VERSION," (",?COPYRIGHT,")",cr,lf)
		invoke FileTimeToSystemTime, addr m_filetime, addr _st
		movzx eax, _st.wYear
		movzx edx, _st.wMonth
		movzx esi, _st.wDay
		movzx ecx, _st.wHour
		movzx edi, _st.wMinute
		invoke xprintf, CStr(";--- source file: %s, last modified: %u/%u/%u %u:%u",cr,lf),
			m_pszFullPath, edx, esi, eax, ecx, edi
		invoke GetCommandLine            
		mov esi, eax
		xor eax, eax
		.while (byte ptr [esi])
			lodsb
			.if (al == '"')
				xor ah,1
			.endif
			.break .if (ax == ' ')
		.endw
		invoke xprintf, CStr(";--- cmdline used for creation: %s",cr,lf,cr,lf), esi
		.repeat
			invoke ParseC
		.until (!eax)
		.if (m_bIfLvl)
			invoke printf, CStr("%s, %u: unmatching if/endif",lf),
				m_pszFileName, m_dwLine
			inc m_dwErrors
		.endif
		invoke write, CStr(cr,lf)
		.if (m_dwWarnings)
			invoke xprintf, CStr(";--- warnings: %u",cr,lf), m_dwWarnings
		.endif
		invoke xprintf, CStr(";--- errors: %u",cr,lf), m_dwErrors
		invoke xprintf, CStr(";--- end of file ---",cr,lf)
		dprintf <"Analyzer@IncFile end %s",lf>, m_pszFileName

		ret

Analyzer@IncFile endp

;--- parser subroutines

;--- parser: skip comments "/* ... */" in a line

skipcomments proc uses edi esi pszLine:LPSTR

local	szChar[2]:byte

	.if (g_bIncludeComments)
		mov edi, m_pszOut
		mov al,PP_COMMENT
		stosb
	.endif
	mov esi, pszLine
	mov al,00
	.while (1)
		mov ah,al
		lodsb
		.break .if (al == 0)
		.break .if ((ax == "//") && (!m_bComment))
		.if (m_bComment && (ax == "*/"))
			mov word ptr [esi-2],2020h
;;			dec m_bComment
			mov m_bComment, FALSE
		.endif
;;		.if (ax == '/*')
		.if ((ax == '/*') && (!m_bComment))
;;			inc m_bComment
			mov m_bComment, TRUE
			mov word ptr [esi-2],2020h
		.endif
		.if (m_bComment)
			.if (g_bIncludeComments)
				stosb
			.endif
			mov byte ptr [esi-1],' '
		.endif
	.endw
	.if (g_bIncludeComments)
		.if (byte ptr [edi-1] == PP_COMMENT)
			mov byte ptr [edi-1],0
		.else
			mov al,00
			stosb
			mov m_pszOut, edi
		.endif
	.endif
	ret
skipcomments endp

;--- ConvertNumber: esi = input stream, edi = output stream
;--- converts number from C syntax to MASM syntax
;--- must preserve ecx edx

ConvertNumber proc uses ecx edx

		xor eax, eax
		mov cx,[esi]
		.if ((cx == "x0") || (cx == "X0"))
			add esi,2
			.if (byte ptr [esi] > '9')
				mov al,'0'
				stosb
			.endif
			mov dl,1
		.else
			mov dl,0
		.endif
		xor ecx,ecx
		.while (1)
			mov al,[esi]
			invoke IsAlphaNumeric
			.if (CARRY?)
				.if (al == '.')
					or dl,2
				.else
					.break
				.endif
			.endif
			movsb
			inc ecx
		.endw
		mov dh,0
		.if (ecx > 3)
			mov ax,[edi-3]
			or	ax,2020h
			.if (al == "i")
				mov ax,[edi-2]
				.if ((ax == "46") || (ax == "23") || (eax == "61"))
					lea edi, [edi-3]
					inc dh
				.endif
			.elseif ((ah == "i") && (byte ptr [edi-1] == '8'))
				lea edi, [edi-2]
				inc dh
			.elseif (ecx > 4)
				mov eax,[edi-4]
				or al, 20h
				.if (eax == "821i")
					lea edi,[edi-4]
					inc dh
				.endif
			.endif
			.if (dh)
				mov al,[edi-1]
				or al,20h
				.if (al == 'u')
					dec edi
				.endif
				jmp skip1
			.endif
		.endif
		.if (ecx > 1)
			mov al,[edi-1]
			or al,20h
			.if ((al == 'l') || (al == 'u'))
				dec edi
				.if (ecx > 2)
					mov ah,[edi-1]
					or ah,20h
					.if ((ah != al) && (ah == 'u'))
						dec edi
					.endif
				.endif
			.elseif (al == 'e')
				test dl,2
				.if (!ZERO?)
					mov byte ptr [edi-1],'E'
					mov al,[esi]
					.if ((al == '-') || (al == '+'))
						movsb
						.while (1)
							mov al,[esi]
							.if (al >= 'A')
								or al, 20h
							.endif
							.if (((al >= '0') && (al <= '9')) || (al == 'f') || (al == 'l'))
								movsb
							.else
								.break
							.endif
						.endw
					.endif
				.endif
			.endif
			test dl,2
			.if (!ZERO?)
				mov al,[edi-1]
				or al,20h
				.if ((al == 'f') || (al == 'l'))
					dec edi
				.endif
			.endif
		.endif
skip1:
		test dl,1
		.if (!ZERO?)
			mov al,'h'
			stosb
		.endif
		ret
ConvertNumber endp

szBell		equ <'07'>
szBackSp	equ <'08'>
szHTab		equ <'09'>
szLF		equ <'0A'>
szVTab		equ <'0B'>
szFF		equ <'0C'>
szCR		equ <'0D'>

addescstr proc
	push eax
	.if (!ch)
		mov al,'"'
		stosb
	.endif
	.if (!(ch & 2))
		mov al,','
		stosb
	.endif
	pop eax
	xchg al,ah
	stosw
	mov al,'h'
	stosb
	ret
addescstr endp

;--- preserve ecx, edx!
;--- ch: bit 0=1: previous item is enclosed in '"'
;---     bit 1=1: no previous char

GetStringLiteral proc uses ecx
		mov ch,2
		.repeat
			lodsb
			.if (al == '\')
				lodsb
				.if ((al >= '0') && (al <= '7'))
					.if (!ch)
						mov al,'"'
						stosb
					.endif
					mov al,','
					stosb
					dec esi
					mov cl,3
					.while (cl)
						mov al,[esi]
						.if (al >= '0' && al <= '7')
							stosb
						.else
							.break
						.endif
						inc esi
						dec cl
					.endw
					.if (cl != 3)
						mov al,'o'
						stosb
					.endif
				.elseif (al == 'a')
					mov ax,szBell
					invoke addescstr
				.elseif (al == 'b')
					mov ax,szBackSp
					invoke addescstr
				.elseif (al == 'f')
					mov ax,szFF
					invoke addescstr
				.elseif (al == 'n')
					mov ax,szLF
					invoke addescstr
				.elseif (al == 'r')
					mov ax,szCR
					invoke addescstr
				.elseif (al == 't')
					mov ax,szHTab
					invoke addescstr
				.elseif (al == 'v')
					mov ax,szVTab
					invoke addescstr
				.elseif (al == 'x')
					.if (!ch)
						mov al,'"'
						stosb
					.endif
					mov al,','
					stosb
					mov cl,3
					.while (cl)
						mov al,[esi]
						or al,20h
						.if (al >= '0' && al <= '9')
							stosb
						.elseif (al >= 'a' && al <= 'f')
							.if (cl == 3)
								mov byte ptr [edi],'0'
								inc edi
							.endif
							stosb
						.else
							.break
						.endif
						inc esi
						dec cl
					.endw
					.if (cl != 3)
						mov al,'h'
						stosb
					.endif
				.elseif (al == '"')
					.if (ch)
						mov al,','
						stosb
						mov al,'"'
						stosb
					.endif
					stosb
					stosb
					mov ch,0
					.continue
				.else
					jmp normalchar
				.endif
				mov ch,1
				.continue
			.endif
normalchar:
			.if (ch)
				.if (al == '"')
					.break
				.else
					mov ah,al
					.if (ch & 1)
						mov al,','
						stosb
					.endif
					mov al,'"'
					stosb
					mov al,ah
				.endif
			.endif
			.if (!al)
				dec esi
				mov al,'"'
			.endif
			stosb
			mov ch,0
		.until (al == '"')
;------------------------------ dont add terminating 0!
;------------------------------ this won't work for strings as macro
;------------------------------ parameters: DECLSPEC_GUID("xxxxxxxx-xxxx...")
if ?ADDTERMNULL
		mov ax,"0,"
		stosw
endif
		ret
GetStringLiteral endp

GetWStringLiteral proc
	stosb
	mov al,'('
	stosb
	lodsb
	call GetStringLiteral
	mov al,')'
	stosb
	ret
GetWStringLiteral endp

;--- parse a source line

parseline proc uses esi edi pszLine:ptr byte, bWeak:DWORD

local	bIsPreProc:BYTE
local	bIsDefine:BYTE

	mov bIsPreProc, FALSE
	mov bIsDefine, FALSE
	mov esi,pszLine
	.if (byte ptr [esi] == '#')
		mov bIsPreProc, TRUE
	.endif
	invoke skipcomments, esi
	mov edi, m_pszOut
	xor ecx, ecx			;token counter
	.while (1)
		mov al,[esi]
		.break .if (al == 0)
		mov edx, edi		;edx holds start of token
		.if ((al == '/') && (byte ptr [esi+1] == '/'))
			.if (g_bIncludeComments)
				mov al, PP_COMMENT
				stosb
				invoke lstrcpy, edi, esi
				invoke lstrlen, edi
				add edi, eax
				inc edi
			.endif
			.break
		.endif
;------------------------ get 1 token
		.while (1)
			.break .if (byte ptr [esi] == 0)
			lodsb
			.break .if ((al == ' ') || (al == 9))
			.if ((edi == edx) && (al == '"'))
				invoke GetStringLiteral
				.break
			.endif
			.if ((edi == edx) && (al == 'L') && (byte ptr [esi] == '"'))
				invoke GetWStringLiteral
				.break
			.endif
if 1
			.if ((edi == edx) && (al >= '0') && (al <= '9'))
				dec esi
				invoke ConvertNumber	;preserves ecx, edx
				.break
			.endif
endif
			call IsDelim	;no register changes!
			.if (ZERO?)
				.if (edi != edx)
					.if ((al == '(') && bIsDefine && (ecx == 2))
						mov al,0
						stosb
						mov ax, PP_MACRO
						stosb
					.endif
					dec esi
				.else
					stosb
					mov ah,[esi]
					invoke IsTwoCharOp
					.if (ZERO?)
						movsb
					.endif
				.endif
				.break
			.endif
			stosb
		.endw
		.if (edx != edi)
			mov byte ptr [edi],0
			inc edi
			inc ecx
			.if ((ecx == 2) && (bIsPreProc))
				.if ((dword ptr [edx+0] == "ifed") && (word ptr [edx+4] == "en"))
					mov bIsDefine, TRUE
				.endif
			.endif
		.endif
	.endw
	.if (bWeak)
		mov ax,PP_WEAKEOL
	.else
		mov ax,PP_EOL
	.endif
	stosw
	mov m_pszOut, edi
	ret
parseline endp

;--- get a source text line
;--- 1. skip any white spaces at the beginning
;--- 2. check '\' for preprocessor lines (weak EOL)
;--- 3. call parseline
;--- 4. adjust m_pszIn
;--- return line length in eax (0 is EOF)

Parse_Line proc uses esi edi

	mov esi, m_pszIn
	.while ((byte ptr [esi] == ' ') || (byte ptr [esi] == tab))
		inc esi
	.endw
	mov edx, esi
	xor edi, edi
	.while (1)
		.break .if (byte ptr [esi] == 0)
		lodsb
		.if ((al == cr) || (al == lf))
			mov byte ptr [esi-1],0
			.if (!edi)
				lea edi, [esi-1]
			.endif
			.break .if (al == lf)
		.endif
	.endw
	.if (esi != m_pszIn)
		inc m_dwLine
	.endif

	mov ah,00
	.if (m_bContinuation || (byte ptr [edx] == '#'))
		mov m_bContinuation, FALSE
		mov ecx, edi
		.while (ecx >= edx)
			mov al,[ecx]
			.if (al == '\')
				.while (byte ptr [ecx])
					mov byte ptr [ecx],' '
					inc ecx
				.endw
				mov ah,01
				mov m_bContinuation, TRUE
				.break
			.endif
			.break .if (al >= ' ')
			dec ecx
		.endw
	.endif

	movzx ecx, ah
	invoke parseline, edx, ecx

	mov eax, esi
	sub eax, m_pszIn
	mov m_pszIn, esi
	ret
Parse_Line endp

;--- the parser
;--- input is C header source
;--- output is tokenized, that is:
;--- + each token is an asciiz string
;--- + numeric literals (numbers) are converted to ASM already
;--- + comments are marked as such
;--- example:
;--- input: "#define VAR1 0xA+2"\r\n
;--- output: "#define",0,"VAR1",0,"0Ah",0,"+",0,"2",0,PP_EOL,0

Parser@IncFile proc public uses _this pThis:ptr INCFILE
	mov _this, pThis
	mov m_dwLine, 1
	mov m_bContinuation, FALSE
	.repeat
		invoke Parse_Line
	.until (!eax)
	mov eax, m_pszOut
	mov byte ptr [eax],0
	ret
Parser@IncFile endp

;--- write output buffer to file
;--- eax=0 if error

Write@IncFile proc public uses _this edi pThis:ptr INCFILE, pszFileName:LPSTR

local	rc:DWORD
local	hFile:DWORD

	mov _this, pThis
	mov rc,1
	invoke lstrlen, m_pBuffer1
	.if (eax)
		mov edi, eax
		invoke _lcreat, pszFileName, 0
		.if (eax != -1)
			mov hFile, eax
			invoke _lwrite, hFile, m_pBuffer1, edi
			.if (eax != edi)
				invoke GetLastError
				invoke printf, CStr("%s: write error [%X]",lf), pszFileName, eax
				mov rc, 0
			.endif
			invoke _lclose, hFile
		.else
			invoke GetLastError
			invoke printf, CStr("cannot create file %s [%X]",lf), pszFileName, eax
			mov rc, 0
		.endif
	.endif
	mov eax, rc
	ret

Write@IncFile endp

;--- write to file
;--- eax=0 if error

WriteDef@IncFile proc public uses _this edi pThis:ptr INCFILE, pszFileName:LPSTR

local	hFile:DWORD
local	rc:DWORD
local	szFile[MAX_PATH]:BYTE
local	szText[512]:BYTE

		mov _this, pThis

		mov rc,0
		.if (!m_pDefs)
;;			invoke printf, CStr("no .DEF file requested",10)
			jmp @exit
		.endif
		invoke GetNumItems@List, m_pDefs
		.if (!eax)
			.if (g_bWarningLevel > 2)
				invoke printf, CStr("no items for .DEF file",10)
			.endif
			jmp @exit
		.endif

		invoke lstrcpy, addr szFile, pszFileName
		invoke lstrlen, pszFileName
		lea ecx, szFile
		.if ((eax < 5) || (byte ptr [ecx+eax-4] != '.'))
			invoke printf, CStr("invalid file name %s for .DEF file",10), pszFileName
			jmp @exit
		.endif
		mov pszFileName, ecx
		mov dword ptr [ecx+eax-3],"FED"

		invoke SortCS@List, m_pDefs

		invoke	_lcreat, pszFileName, 0
		.if (eax != -1)
			mov hFile, eax
			invoke _lwrite, hFile, CStr("LIBRARY",13,10),7+2
			invoke _lwrite, hFile, CStr("EXPORTS",13,10),7+2
			invoke GetItem@List, m_pDefs, 0
			.while (eax)
				mov edi, eax
				invoke sprintf, addr szText, CStr(" ",22h,"%s",22h,13,10), [eax].NAMEITEM.pszName
				invoke _lwrite, hFile, addr szText, eax
				invoke GetItem@List, m_pDefs, edi
			.endw
			invoke _lclose, hFile
			mov rc,1
		.else
			invoke GetLastError
			invoke printf, CStr("cannot create file %s [%X]",lf), pszFileName, eax
		.endif
@exit:
		mov eax, rc
		ret

WriteDef@IncFile endp

GetFileName@IncFile proc public uses _this pThis:ptr INCFILE
		mov _this, pThis
		mov eax, m_pszFileName
		mov edx, m_dwLine
		ret
GetFileName@IncFile endp

GetFullPath@IncFile proc public uses _this pThis:ptr INCFILE
		mov _this, pThis
		mov eax, m_pszFullPath
		ret
GetFullPath@IncFile endp

if 0
GetLine@IncFile proc public uses _this pThis:ptr INCFILE
		mov _this, pThis
		mov eax, m_dwLine
		ret
GetLine@IncFile endp
endif

GetParent@IncFile proc public uses _this pThis:ptr INCFILE
		mov _this, pThis
		mov eax, m_pParent
		ret
GetParent@IncFile endp

;--- constructor include file object
;--- returns:
;---  eax = 0 if error occured
;---  eax = _this if ok

Create@IncFile proc public uses _this pszFileName:LPSTR, pParent:ptr INCFILE

local	hFile:dword
local	dwFileSize:dword
local	ftLastWrite:FILETIME
local	szFileName[MAX_PATH]:byte

if ?USELOCALALLOC
		invoke LocalAlloc, LMEM_FIXED or LMEM_ZEROINIT, sizeof INCFILE
else
		invoke _malloc, sizeof INCFILE
endif
		.if (!eax)
			jmp @exit
		.endif
		mov _this, eax
ife ?USELOCALALLOC
		invoke ZeroMemory, _this, sizeof INCFILE
endif

		invoke _splitpath, pszFileName, NULL, NULL, addr g_szName, addr g_szExt
		invoke	_lopen, pszFileName, OF_READ or OF_SHARE_COMPAT
		.if (eax == -1)
			.if (g_pszIncDir)
				invoke _makepath, addr szFileName, NULL, g_pszIncDir, addr g_szName, addr g_szExt
				invoke	_lopen, addr szFileName, OF_READ or OF_SHARE_COMPAT
				.if (eax != -1)
					lea ecx, szFileName
					mov pszFileName, ecx
					jmp file_exists
				.endif
			.endif
			.if (pParent)
				invoke GetFileName@IncFile, pParent
				invoke printf, CStr("%s, %u: "), eax, edx
			.endif
			invoke GetLastError
			invoke printf, CStr("cannot open file %s [%X]",lf), pszFileName, eax
if ?USELOCALALLOC
			invoke LocalFree, _this            
else
			invoke _free, _this
endif
			xor eax, eax
			jmp @exit
		.endif
file_exists:
		mov hFile,eax
		invoke AddString, pszFileName, 0
		mov m_pszFullPath, eax
		invoke _makepath, addr szFileName, NULL, NULL, addr g_szName, addr g_szExt
		invoke AddString, addr szFileName, 0
		mov m_pszFileName, eax
		invoke GetFileTime, hFile, NULL, NULL, addr ftLastWrite
		invoke FileTimeToLocalFileTime, addr ftLastWrite, addr m_filetime
		
		invoke GetFileSize, hFile, NULL
		mov dwFileSize, eax
		mov ecx, eax
if ?ADD50PERCENT
		shr ecx, 1			;add 50% to file size for buffer size
endif
		add eax, ecx
		mov m_dwBufSize, eax
		invoke VirtualAlloc, 0, m_dwBufSize, MEM_COMMIT, PAGE_READWRITE
		.if (eax)
			mov m_pBuffer1, eax
			dprintf <"alloc buffer 1 for %s returned %X",lf>, m_pszFileName, eax
			invoke VirtualAlloc, 0, m_dwBufSize, MEM_COMMIT, PAGE_READWRITE
			mov m_pBuffer2, eax
			dprintf <"alloc buffer 2 for %s returned %X",lf>, m_pszFileName, eax
		.endif
		.if (!eax)
			invoke printf, CStr("fatal error: out of memory",lf)
if ?USELOCALALLOC
			invoke LocalFree, _this
else
			invoke _free, _this
endif
			mov g_bTerminate, TRUE
			xor eax, eax
			jmp @exit
		.endif
		invoke _lread, hFile, m_pBuffer1, dwFileSize
		push eax
		invoke _lclose, hFile
		pop eax
		mov ecx, m_pBuffer1
		mov byte ptr [ecx+eax],0
		mov m_pszIn, ecx
		mov ecx, m_pBuffer2
		mov byte ptr [ecx],0
		mov m_pszOut, ecx
		mov eax, pParent
		mov m_pParent, eax
		mov m_bNewLine, TRUE
		mov eax, _this
@exit:
		ret
Create@IncFile endp

;--- destructor include file object

Destroy@IncFile proc public uses _this pThis:ptr INCFILE
	mov _this, pThis
	dprintf <"free buffer 1 %X for %s",lf>, m_pBuffer1, m_pszFileName
	invoke VirtualFree, m_pBuffer1, 0, MEM_RELEASE
	dprintf <"free buffer 2 %X for %s",lf>, m_pBuffer2, m_pszFileName
	invoke VirtualFree, m_pBuffer2, 0, MEM_RELEASE
	.if (m_pDefs)
		invoke Destroy@List, m_pDefs
		mov m_pDefs, NULL
	.endif
if ?USELOCALALLOC
	invoke LocalFree, _this
else
	invoke _free, _this
endif
	ret
Destroy@IncFile endp

	end
