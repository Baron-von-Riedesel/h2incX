
;--- creates MASM INC files from H files

;--- todo: #include may contain a relative path
;--- currently h2incx seems to be confused by that (GL\GLU.H)
;--- todo: numerical constants beginning with 0 (not 0x)
;--- are octals!

	.386
	.model flat, stdcall
	option casemap:none
	option proc:private

	.nolist
	.nocref
	include winbase.inc
	include stdlib.inc
	include stdio.inc
	include conio.inc		;needed because _getch is used
	include macros.inc
	include try.inc
	include excpt.inc
	.list
	.cref
	include h2incX.inc
	include CIncFile.inc
	include CList.inc

?STRINGPOOLMAX	equ 1000000h;address space reserved	for string pool
?STRINGPOOLSIZE	equ 10000h
?MAXWARNINGLVL	equ 3		;max value for -Wn switch

	.DATA

;--- global vars

g_pStringPool		LPSTR 0	;string pool memory (=heap)
g_pStringPoolMax	LPSTR 0	;string pool memory end
g_pStringPtr		dd 0	;ptr to free string pool memory
g_rc				dd 0
g_pszFilespec		LPSTR 0	;filespec cmdline param
g_pszOutDir			LPSTR 0	;-o cmdline output directory
g_pszIncDir			LPSTR 0	;-I cmdline include directory
g_dwStructSuffix	dd 0	;number used for nameless structures
g_dwDefCallConv		dd 0	;default calling convention
g_pInpFiles			dd 0	;linked list of processed input files
g_pStructures		dd 0	;list of structures defined in cur. file
g_pMacros			dd 0	;list of macros defined in cur. file
if ?PROTOSUMMARY
g_pPrototypes		dd 0	;list of prototypes
endif
if ?TYPEDEFSUMMARY
g_pTypedefs			dd 0	;list of typedefs
endif
if ?DYNPROTOQUALS
g_pQualifiers		dd 0	;list of prototype qualifiers
endif

g_ReservedWords		SORTARRAY <0,0>	;profile file strings [Reserved Words]
g_KnownStructures	SORTARRAY <0,0>	;profile file strings
g_ProtoQualifiers	SORTARRAY <0,0>	;profile file strings
g_ppSimpleTypes		dd 0	;profile file strings [Simple Types]
g_ppKnownMacros		dd 0	;profile file strings [Macro Names]
g_ppTypeAttrConv	dd 0	;profile file strings
g_ppConvertTokens	dd 0	;profile file strings
g_ppConvertTypes1	dd 0	;profile file strings
g_ppConvertTypes2	dd 0	;profile file strings
g_ppConvertTypes3	dd 0	;profile file strings
g_ppAlignments		dd 0	;profile file strings
g_ppTypeSize		dd 0	;profile file strings

g_bTerminate		db FALSE;1=terminate app as soon as possible

g_bAddAlign			db FALSE;-a cmdline switch
g_bBatchmode		db FALSE;-b cmdline switch
g_bIncludeComments	db FALSE;-c cmdline switch
g_bAssumeDllImport	db FALSE;-d cmdline switch
g_bUseDefProto		db FALSE;-D	cmdline switch
g_bCreateDefs		db FALSE;-e cmdline switch
g_bIgnoreDllImport	db FALSE;-g cmdline switch
g_bProcessInclude	db FALSE;-i cmdline switch
g_bUntypedMembers	db FALSE;-m cmdline switch
if ?PROTOSUMMARY
g_bProtoSummary		db FALSE;-p cmdline switch
endif
g_bNoRecords		db FALSE;-q cmdline switch
g_bRecordsInUnions	db FALSE;-r cmdline switch
g_bSummary			db FALSE;-S cmdline switch
if ?TYPEDEFSUMMARY
g_bTypedefSummary	db FALSE;-t cmdline switch
endif
g_bUntypedParams	db FALSE;-u cmdline switch
g_bVerbose			db FALSE;-v cmdline switch
g_bWarningLevel		db 0	;-W cmdline switch
g_bOverwrite		db FALSE;-y cmdline switch

g_bOutDirExpected	db FALSE;temp var for -o cmdline switch
g_bSelExpected		db FALSE;temp var for -s cmdline switch
g_bCallConvExpected db FALSE;temp var for -k cmdline switch
g_bIncDirExpected	db FALSE;temp var for -k cmdline switch

g_bPrototypes		db TRUE	;modified by -s cmdline switch
g_bTypedefs			db TRUE	;modified by -s cmdline switch
g_bConstants		db TRUE	;modified by -s cmdline switch
g_bExternals		db TRUE	;modified by -s cmdline switch

;--- table for sections to read from h2incx.ini

CONVTABENTRY struct
pszSection	dd ?	;section name
pPtr		dd ?	;pointer to table pointer or SORTARRAY
pDefault	dd ?	;pointer to default value table
dwFlags		dd ?	;
CONVTABENTRY ends

CF_ATOL	equ 0001h	;convert every 2. string to a number
CF_SORT	equ 0002h	;sort table (then pPtr must point to a SORTARRAY)
CF_CASE	equ 0004h	;strings are case-insensitive

;--- default tables marked with CF_ATOL, CF_SORT or CF_CASE must be in .data!

convtab label dword
	CONVTABENTRY <CStr("Simple Type Names"), offset g_ppSimpleTypes, offset g_SimpleTypesDefault, 0>
	CONVTABENTRY <CStr("Macro Names"), offset g_ppKnownMacros, offset g_KnownMacrosDefault, CF_ATOL>
	CONVTABENTRY <CStr("Structure Names"), offset g_KnownStructures, offset g_KnownStructuresDefault, CF_SORT>
	CONVTABENTRY <CStr("Reserved Words"), offset g_ReservedWords, offset g_ReservedWordsDefault, CF_CASE or CF_SORT>
	CONVTABENTRY <CStr("Type Qualifier Conversion"), offset g_ppTypeAttrConv, offset g_TypeAttrConvDefault, 0>
	CONVTABENTRY <CStr("Type Conversion 1"), offset g_ppConvertTypes1, offset g_ConvertTypes1Default, 0>
	CONVTABENTRY <CStr("Type Conversion 2"), offset g_ppConvertTypes2, offset g_ConvertTypes2Default, 0>
	CONVTABENTRY <CStr("Type Conversion 3"), offset g_ppConvertTypes3, offset g_ConvertTypes3Default, 0>
	CONVTABENTRY <CStr("Token Conversion"), offset g_ppConvertTokens, offset g_ConvertTokensDefault, 0>
	CONVTABENTRY <CStr("Prototype Qualifiers"), offset g_ProtoQualifiers, offset g_ProtoQualifiersDefault, CF_ATOL or CF_SORT>
	CONVTABENTRY <CStr("Alignment"), offset g_ppAlignments, offset g_AlignmentsDefault, 0>
	CONVTABENTRY <CStr("Type Size"), offset g_ppTypeSize, offset g_TypeSizeDefault, CF_ATOL>
	dd 0

;--- token conversion
;--- use with care

g_ConvertTokensDefault label dword
	dd CStr("interface"),CStr("struct")
	dd 0

;--- known type attribute names
;--- usually not used, since defined in h2incx.ini

g_TypeAttrConvDefault label dword
	dd CStr("*far"), CStr("")
	dd CStr("*near"), CStr("")
	dd CStr("IN"), CStr("")
	dd CStr("OUT"), CStr("")
	dd 0

;--- known macro names
;--- usually not used, since defined in h2incx.ini

g_KnownMacrosDefault label dword
	dd CStr("DECLARE_HANDLE"), 0
	dd CStr("DECLARE_GUID"), 0
	dd 0

;--- known structure names
;--- usually not used, since defined in h2incx.ini

g_KnownStructuresDefault label dword
	dd CStr("POINT")
	dd 0

;--- structure sizes. required if a structure is a parameter
;--- with size > 4 

g_TypeSizeDefault label dword
	dd CStr("CY"), 8
	dd CStr("DATE"), 8
	dd CStr("DOUBLE"), 8
	dd CStr("POINT"), 8
	dd CStr("VARIANT"), 16
	dd 0

;--- known prototype qualifier names
;--- usually not used, since defined in h2incx.ini

PROTOQUAL struct
pszName		LPSTR ?
dwValue		DWORD ?
PROTOQUAL ends

g_ProtoQualifiersDefault label dword
	PROTOQUAL <CStr("__cdecl"), FQ_CDECL>
	PROTOQUAL <CStr("_cdecl"), FQ_CDECL>
	PROTOQUAL <CStr("__stdcall"), FQ_STDCALL>
	PROTOQUAL <CStr("_stdcall"), FQ_STDCALL>
	PROTOQUAL <CStr("stdcall"), FQ_STDCALL>
	PROTOQUAL <CStr("WINAPI"), FQ_STDCALL>
	PROTOQUAL <CStr("WINAPIV"), FQ_CDECL>
	PROTOQUAL <CStr("APIENTRY"), FQ_STDCALL>
	PROTOQUAL <CStr("__inline"), FQ_INLINE>
	dd 0

;--- simple types default
;--- usually not used, since defined in h2incx.ini

g_SimpleTypesDefault label dword
	dd CStr("BYTE")
	dd CStr("SBYTE")
	dd CStr("WORD")
	dd CStr("SWORD")
	dd CStr("DWORD")
	dd CStr("SDWORD")
	dd CStr("QWORD")
	dd CStr("LONG")
	dd CStr("ULONG")
	dd CStr("REAL4")
	dd CStr("REAL8")
	dd CStr("BOOL")
	dd CStr("CHAR")
	dd CStr("ptr")
	dd CStr("PVOID")
	dd CStr("WCHAR")
	dd CStr("WPARAM")
	dd CStr("LPARAM")
	dd CStr("LRESULT")
	dd CStr("HANDLE")
	dd CStr("HINSTANCE")
	dd CStr("HGLOBAL")
	dd CStr("HLOCAL")
	dd CStr("HWND")
	dd CStr("HMENU")
	dd CStr("HDC")
	dd 0

;--- type conversion 1 default
;--- usually not used since defined in h2incx.ini

g_ConvertTypes1Default label dword
	dd CStr("DWORDLONG"), CStr("QWORD")
	dd CStr("ULONGLONG"), CStr("QWORD")
	dd CStr("LONGLONG"), CStr("QWORD")
	dd CStr("double"), CStr("REAL8")
	dd 0

;--- type conversion 2 default
;--- usually not used since defined in h2incx.ini

g_ConvertTypes2Default label dword
	dd CStr("int"), CStr("SDWORD")
	dd CStr("unsigned int"), CStr("DWORD")
	dd CStr("short"), CStr("SWORD")
	dd CStr("unsigned short"), CStr("WORD")
	dd CStr("long"), CStr("SDWORD")
	dd CStr("unsigned long"), CStr("DWORD")
	dd CStr("char"), CStr("SBYTE")
	dd CStr("unsigned char"), CStr("BYTE")
	dd CStr("wchar_t"), CStr("WORD")
	dd CStr("LPCSTR"), CStr("LPSTR")
	dd CStr("LPCWSTR"), CStr("LPWSTR")
	dd CStr("UINT"), CStr("DWORD")
	dd CStr("ULONG"), CStr("DWORD")
	dd CStr("LONG"), CStr("SDWORD")
	dd CStr("FLOAT"), CStr("REAL4")
	dd 0

;--- type conversion 3 default
;--- usually not used since defined in h2incx.ini

g_ConvertTypes3Default label dword
	dd CStr("POINT"), CStr("QWORD")
	dd CStr("VARIANT"), CStr("VARIANT")
	dd 0

;--- structure alignments default
;--- usually not used since defined in h2incx.ini

g_AlignmentsDefault label dword
	dd 0

;--- reserved words default
;--- usually not used since defined in h2incx.ini

g_ReservedWordsDefault label dword
	dd CStr("cx")
	dd CStr("dx")
	dd 0

	.const

;--- command line switch table

CLSWITCH struct
bSwitch	db ?
bType	db ?
pVoid	dd ?
CLSWITCH ends

CLS_ISBOOL	equ 1
CLS_ISPROC	equ 2	;not used

clswitchtab label byte
	CLSWITCH <'a',CLS_ISBOOL, offset g_bAddAlign>
	CLSWITCH <'b',CLS_ISBOOL, offset g_bBatchmode>
	CLSWITCH <'c',CLS_ISBOOL, offset g_bIncludeComments>
;	CLSWITCH <'d',CLS_ISBOOL, offset g_bAssumeDllImport>
;	CLSWITCH <'D',CLS_ISBOOL, offset g_bUseDefProto>
;	CLSWITCH <'g',CLS_ISBOOL, offset g_bIgnoreDllImport>
	CLSWITCH <'e',CLS_ISBOOL, offset g_bCreateDefs>
	CLSWITCH <'i',CLS_ISBOOL, offset g_bProcessInclude>
	CLSWITCH <'I',CLS_ISBOOL, offset g_bIncDirExpected>
	CLSWITCH <'k',CLS_ISBOOL, offset g_bCallConvExpected>
;	CLSWITCH <'m',CLS_ISBOOL, offset g_bUntypedMembers>
	CLSWITCH <'o',CLS_ISBOOL, offset g_bOutDirExpected>
if ?PROTOSUMMARY
	CLSWITCH <'p',CLS_ISBOOL, offset g_bProtoSummary>
endif
	CLSWITCH <'q',CLS_ISBOOL, offset g_bNoRecords>
	CLSWITCH <'r',CLS_ISBOOL, offset g_bRecordsInUnions>
	CLSWITCH <'s',CLS_ISBOOL, offset g_bSelExpected>
	CLSWITCH <'S',CLS_ISBOOL, offset g_bSummary>
if ?TYPEDEFSUMMARY
	CLSWITCH <'t',CLS_ISBOOL, offset g_bTypedefSummary>
endif
	CLSWITCH <'u',CLS_ISBOOL, offset g_bUntypedParams>
	CLSWITCH <'v',CLS_ISBOOL, offset g_bVerbose>
	CLSWITCH <'y',CLS_ISBOOL, offset g_bOverwrite>
	db 0

szUsage label byte
	db "h2incx ",?VERSION,", ",?COPYRIGHT,lf
	db "usage: h2incx <options> filespec",lf
	db "  -a: add @align to STRUCT declarations",lf
	db "  -b: batch mode, no user interaction",lf
	db "  -c: include comments in output",lf
	db "  -d0|1|2|3: define __declspec(dllimport) handling:",lf
	db "     0: [default] decide depending on values in h2incx.ini",lf
	db "     1: always assume __declspec(dllimport) is set",lf
	db "     2: always assume __declspec(dllimport) is not set",lf
	db "     3: if possible use @DefProto macro to define prototypes",lf
	db "  -e: write full decorated names of function prototypes to a .DEF file",lf
	db "  -i: process #include lines",lf
	db "  -I directory: specify an additionally directory to search for header files",lf
	db "  -k c|s|p|y: set default calling convention for prototypes",lf
	db "  -o directory: set output directory (default is current dir)",lf
if ?PROTOSUMMARY
	db "  -p: print prototypes in summary",lf
endif
	db "  -q: avoid RECORD definitions",lf
	db "  -r: create size-safe RECORD definitions",lf
	db "  -s c|p|t|e: selective output, c/onstants,p/rototypes,t/ypedefs,e/xternals",lf
Summary1	textequ <!"  -S: print summary (structures, macros> 	   
Summary2	textequ <>
Summary3	textequ <>
Summary4	textequ <!)!",lf>
if ?PROTOSUMMARY
Summary2	textequ < !<, prototypes!>>
endif
if ?TYPEDEFSUMMARY
Summary3	textequ < !<, typedefs!>>
endif
SummaryStr	textequ @CatStr(%Summary1, %Summary2, %Summary3, %Summary4)
	db SummaryStr
if ?TYPEDEFSUMMARY
	db "  -t: print typedefs in summary",lf
endif
	db "  -u: generate untyped parameters (DWORDs) in prototypes",lf
	db "  -v: verbose mode",lf
	db "  -W0|1|2|3: set warning level (default is 0)",lf
	db "  -y: overwrite existing .INC files without confirmation",lf
	db 0

	.DATA?

g_szDrive	db 4	dup (?)
g_szDir		db 256	dup (?)
g_szName	db 256	dup (?)
g_szExt		db 256	dup (?)

	.CODE

;--- alloc space in string pool

AllocSpace proc uses esi edi dwSize:DWORD
	mov eax, g_pStringPtr
	mov ecx, dwSize
	add ecx, eax
	cmp ecx, g_pStringPoolMax
	jnc error
	mov g_pStringPtr, ecx
	ret
error:
	xor eax,eax
	ret
AllocSpace endp

;--- add string to string pool
;--- each string has a DWORD value associated with it
;--- which is stored behind the terminating 00

AddString proc public uses esi edi pszString:LPSTR, dwValue:DWORD
	mov edi, pszString
	mov esi, edi
	mov ecx,-1
	mov al,0
	repnz scasb
	not ecx
	mov edi, g_pStringPtr
	lea eax, [edi+ecx+4]
	cmp eax, g_pStringPoolMax
	jnc error
	mov edx,edi
	rep movsb
	mov eax, dwValue
	stosd
	lea eax, [edi+3]
	and al,0FCh
	mov g_pStringPtr, eax
	mov eax, edx
	ret
error:
	xor eax,eax
	ret
AddString endp


_malloc proc stdcall public dwBytes:DWORD
	invoke AllocSpace, dwBytes
	ret
_malloc endp

_free proc stdcall public pMem:LPVOID
	ret
_free endp

if 1
	option prologue:none
	option epilogue:none

_strcmp proc stdcall public a1:ptr byte, a2:ptr byte

strg1	textequ <[esp+4]>
strg2	textequ <[esp+8]>

	mov edx,edi
	mov edi,strg2
	xor eax,eax
	mov ecx,-1
	repne scasb
	not ecx
	sub edi,ecx
	mov eax,esi
	mov esi,strg1
	repz cmpsb
	mov esi,eax
	je @F
	sbb eAX,eAX 		;0 + NC /-1 + C
	sbb eAX,-1			;-1 / 1
	mov edi,edx
	ret 8
@@:
	xor eax,eax
	mov edi,edx
	ret 8
_strcmp endp

	option prologue:prologuedef
	option epilogue:epiloguedef
else
_strcmp equ <lstrcmp>
endif

;--- scan command line for options

;	CLSWITCH <'d',CLS_ISBOOL, offset g_bAssumeDllImport>
;	CLSWITCH <'D',CLS_ISBOOL, offset g_bUseDefProto>
;	CLSWITCH <'g',CLS_ISBOOL, offset g_bIgnoreDllImport>

getoption proc uses esi edi pszArgument:LPSTR

	mov esi, pszArgument
	mov al,[esi]
	.if ((al == '/') || (al == '-'))
		mov ax,[esi+1]
		.if (ah)
			.if (al == 'W')
				sub ah,'0'
				jc error
				cmp ah,?MAXWARNINGLVL
				ja error
				mov g_bWarningLevel,ah
				jmp @exit
			.elseif (al == 'd')
				sub ah,'0'
				jc error
				.if (ah == 0)
					;
				.elseif (ah == 1)
					mov g_bAssumeDllImport, TRUE
				.elseif (ah == 2)
					mov g_bIgnoreDllImport, TRUE
				.elseif (ah == 3)
					mov g_bUseDefProto, TRUE
				.else
					jmp error
				.endif
				jmp @exit
			.else
				jmp error
			.endif
		.endif
;;		or al,20h
		mov edi, offset clswitchtab
		.while ([edi].CLSWITCH.bSwitch)
			.if (al == [edi].CLSWITCH.bSwitch)
				.if ([edi].CLSWITCH.bType == CLS_ISBOOL)
					mov ecx, [edi].CLSWITCH.pVoid
					mov byte ptr [ecx],TRUE
				.endif
				jmp @exit
			.endif
			add edi, sizeof CLSWITCH
		.endw
error:
		stc
		ret
	.else
		.if (g_bOutDirExpected)
			mov g_pszOutDir, esi
			mov g_bOutDirExpected, FALSE
		.elseif (g_bSelExpected)
			mov g_bConstants, FALSE
			mov g_bTypedefs, FALSE
			mov g_bPrototypes, FALSE
			mov g_bExternals, FALSE
			.while (1)
				lodsb
				.break .if (!al)
				or al,20h
				.if (al == 'c')
					mov g_bConstants, TRUE
				.elseif (al == 'e')
					mov g_bExternals, TRUE
				.elseif (al == 'p')
					mov g_bPrototypes, TRUE
				.elseif (al == 't')
					mov g_bTypedefs, TRUE
				.else
					jmp error
				.endif
			.endw
			mov g_bSelExpected, FALSE
		.elseif (g_bCallConvExpected)
			mov ax,[esi]
			.if (ah)
				jmp error
			.endif
			or al,20h
			.if (al == 'c')
				or g_dwDefCallConv, FQ_CDECL
			.elseif (al == 's')
				or g_dwDefCallConv, FQ_STDCALL
			.elseif (al == 'p')
				or g_dwDefCallConv, FQ_PASCAL
			.elseif (al == 'y')
				or g_dwDefCallConv, FQ_SYSCALL
			.else
				jmp error
			.endif
			mov g_bCallConvExpected, FALSE
		.elseif (g_bIncDirExpected)
			mov g_pszIncDir, esi
			mov g_bIncDirExpected, FALSE
		.else
			xchg esi,g_pszFilespec
			and esi,esi
			jnz error
		.endif
	.endif
@exit:
	clc
	ret
getoption endp

;--- profile file access procs

;--- load all strings from a section

LoadStrings proc uses esi edi pszTypes:LPSTR, pTable:ptr
	mov esi, pszTypes
	mov edi, pTable
	xor ecx, ecx
	.while (1)
		mov al,[esi]
		.break .if ((al == 0) || (al == '['))
		.if ((al <= ' ') || (al == ';'))
			.repeat
				lodsb
			.until ((al == 0) || (al == lf))
			.break .if (!al)
		.else
			mov dl,'='
			call _addstring
			.if (al == '=')
				mov dl,0
				call _addstring
			.endif
			.break .if (!al)
		.endif
	.endw
	mov eax, ecx
	dprintf <"LoadStrings()=%u",lf>, eax
	ret
_addstring:
	.if (edi)
		mov [edi], esi
		add edi, 4
	.endif
	inc ecx
	.repeat
		lodsb
	.until ((al == 0) || (al == lf) || (al == dl))
	.if (edi)
		.if (byte ptr [esi-2] == cr)
			mov byte ptr [esi-2],0
		.else
			mov byte ptr [esi-1],0
		.endif
	.endif
	retn
LoadStrings endp

;--- find a section in a profile file (h2incx.ini)

FindSection proc uses esi edi ebx pszSection:LPSTR, pszFile:LPSTR, dwSize:dword

local	dwStrSize:DWORD

	invoke lstrlen, pszSection
	mov dwStrSize, eax
	mov esi, pszFile
	mov ebx, dwSize
	mov al,lf
	.while (ebx)
		mov ah,al
		lodsb
		.if (ax == 0A00h+'[')
			mov edi, pszSection
			mov ecx, dwStrSize
			mov edx, esi
			repz cmpsb
			.if (ZERO?)
				lodsb
				.if (al == ']')
					.repeat
						lodsb
					.until ((al == lf) || (al == 0))
					.if (al == lf)
						mov eax, esi
						jmp @exit
					.endif
				.endif
			.endif
			mov esi, edx
		.endif
		dec ebx
	.endw
	xor eax, eax
@exit:
	dprintf <"FindSection(%s)=%u",lf>, pszSection, eax
	ret
FindSection endp

;--- load strings from various sections in a profile

LoadTablesFromProfile proc uses esi ebx pszInput:LPSTR, dwSize:dword

	mov ebx, offset convtab
	.while ([ebx].CONVTABENTRY.pszSection)
		xor eax, eax
		.if (pszInput)
			invoke FindSection, [ebx].CONVTABENTRY.pszSection, pszInput, dwSize
		.endif
		.if (eax)
			mov esi, eax
			invoke LoadStrings, esi, 0
			inc eax
			shl eax, 2
			.if (eax)
				invoke LocalAlloc, LMEM_FIXED or LMEM_ZEROINIT, eax
				mov ecx, [ebx].CONVTABENTRY.pPtr
				mov [ecx], eax
				.if (eax)
					invoke LoadStrings, esi, eax
				.endif
			.endif
		.else
			mov ecx, [ebx].CONVTABENTRY.pPtr
			mov eax, [ebx].CONVTABENTRY.pDefault
			mov [ecx], eax
		.endif
		add ebx, sizeof CONVTABENTRY
	.endw
	ret
LoadTablesFromProfile endp

;--- read h2incx.ini into a buffer

ReadIniFile proc uses ebx esi

local	dwSize:dword
local	szName[MAX_PATH]:byte

	invoke GetModuleFileName, NULL, addr szName, sizeof szName
	xor esi, esi
	lea ecx, szName
	lea eax, [ecx+eax]
	.while ( eax > ecx )
		.break .if ( byte ptr [eax-1] == '\'  || byte ptr [eax-1] == '/'  || byte ptr [eax-1] == ':' )
		dec eax
	.endw
	invoke strcpy, eax, CStr("h2incx.ini")
	invoke _lopen, addr szName, OF_READ or OF_SHARE_DENY_NONE 
	.if (eax != -1)
		mov ebx, eax
		invoke GetFileSize, ebx, NULL
		mov dwSize, eax
		add eax, 1000h
		and ax, 0F000h
		invoke VirtualAlloc, 0, eax, MEM_COMMIT, PAGE_READWRITE
		.if (eax)
			mov esi, eax
			invoke _lread, ebx, esi, dwSize
			mov byte ptr [esi+eax],0
			mov dwSize, eax
		.else
			invoke printf, CStr("out of memory reading profile file",lf)
		.endif
		invoke _lclose, ebx
	.else
		invoke printf, CStr("profile file %s not found, using defaults!",lf),addr szName
	.endif
	mov eax, esi
	mov edx, dwSize
	ret
ReadIniFile endp

;--- check if output file would be overwritten
;--- if yes, optionally ask user how to proceed
;--- returns: eax=1 -> proceed, eax=0 -> skip processing

CheckIncFile proc uses ebx pszOutName:LPSTR, pszFileName:LPSTR, pParent:ptr INCFILE				 

local	szPrefix[MAX_PATH+32]:byte

	.if (!g_bOverwrite)
		invoke _lopen, pszOutName, OF_READ or OF_SHARE_DENY_NONE 
		.if (eax != -1)
			invoke _lclose, eax
			.if (g_bBatchmode)
				.if ((g_bWarningLevel >= ?MAXWARNINGLVL) || (!pParent))
					.if (pParent)
						invoke GetFileName@IncFile, pParent
						invoke sprintf, addr szPrefix, CStr("%s, %u: "), eax, edx
					.else
						mov szPrefix, 0
					.endif
					invoke printf, CStr("%s%s exists, file %s not processed",lf),
						addr szPrefix, pszOutName, pszFileName
				.endif
				xor eax, eax
				jmp @exit
			.else
				invoke printf, CStr("%s exists, overwrite (y/n)?"), pszOutName
				.while (1)
					invoke _getch
					.if (al >= 'A')
						or al,20h
					.endif
					.break .if (al == 'y')
					.break .if (al == 'n')
					.break .if (al == 3)
				.endw
				push eax
				invoke printf, CStr(lf)
				pop eax
				.if (al == 3)
					mov g_bTerminate, TRUE
					invoke printf, CStr("^C")
					xor eax, eax
					jmp @exit
				.elseif (al == 'n')
					invoke printf, CStr("%s not processed",lf), pszFileName
					xor eax, eax
					jmp @exit
				.endif
			.endif
		.endif
	.endif
	mov eax, 1
@exit:
	ret
CheckIncFile endp

;--- process 1 header file

ProcessFile proc public uses ebx esi pszFileName:LPSTR, pParent:ptr INCFILE

local	pIncFile:ptr INCFILE
local	lpFilePart:LPSTR
local	szFileName[MAX_PATH]:byte
local	szOutName[MAX_PATH]:byte

	invoke GetFullPathName, pszFileName, MAX_PATH, addr szFileName, addr lpFilePart
;;	invoke printf, CStr("ProcessFile, Path=%s, Name=%s, Ext=%s",lf), addr g_szDir, addr g_szName, addr g_szExt
;;	invoke _makepath, addr szFileName, addr g_szDrive, addr g_szDir, addr g_szName, addr g_szExt

;--------------------- dont process files more than once

	lea esi, g_pInpFiles
	mov ebx, [esi+0]
	.while (ebx)
		lea ecx, szFileName
		lea eax, [ebx+4]
		invoke lstrcmpi, eax, ecx
		.if (!eax)
			jmp @exit
		.endif
		mov esi, ebx
		mov ebx,[ebx+0]
	.endw
	invoke lstrlen, addr szFileName
	add eax,1+4
	invoke LocalAlloc, LMEM_FIXED, eax
	.if (!eax)
		jmp @exit
	.endif
	mov [esi+0], eax
	mov dword ptr [eax+0], 0
	lea ecx, [eax+4]
	invoke lstrcpy, ecx, addr szFileName

	.if (g_bVerbose)
		.if (pParent)
			invoke GetFileName@IncFile, pParent
			invoke printf, CStr("%s, %u: "), eax, edx
		.endif
		invoke printf, CStr("file '%s'",lf), pszFileName
	.endif
	invoke _splitpath, addr szFileName, NULL, NULL, addr g_szName, addr g_szExt
	invoke _makepath, addr szOutName, NULL, g_pszOutDir, addr g_szName, CStr(".INC")
;--------------------- check if output file exists
	invoke CheckIncFile, addr szOutName, pszFileName, pParent
	.if (!eax)
		jmp @exit
	.endif

;--------------------- create the object
	invoke Create@IncFile, addr szFileName, pParent
	.if (eax)
		mov pIncFile, eax
		invoke Parser@IncFile, pIncFile
		invoke Analyzer@IncFile, pIncFile
		invoke Write@IncFile, pIncFile, addr szOutName
		push eax
		invoke WriteDef@IncFile, pIncFile, addr szOutName
		invoke Destroy@IncFile, pIncFile
		pop eax
	.endif
@exit:
	ret
ProcessFile endp

cmpproc proc c public p1:ptr, p2:ptr
	mov ecx, p1
	mov edx, p2
	invoke _strcmp, [ecx].NAMEITEM.pszName, [edx].NAMEITEM.pszName
	ret
cmpproc endp

;--- some tables contain strings expected to be numerical values
;--- converted them here

ConvertTables proc uses esi edi ebx

	assume esi:ptr CONVTABENTRY

	mov esi, offset convtab
	.while ([esi].pszSection)
		.if ([esi].dwFlags & CF_ATOL)
			mov ecx, [esi].pPtr
			mov ecx, [ecx]
			.if (ecx != [esi].pDefault)
				mov edi, ecx
				.while (dword ptr [edi])
					mov eax, [edi+4]
					.if (eax)
						invoke atol, eax
						mov [edi+4], eax
					.endif
					add edi, 2*4
				.endw
			.endif
		.endif
		.if ([esi].dwFlags & CF_ATOL)
			mov ebx, 2*4
		.else
			mov ebx, 1*4
		.endif
;----------------------------- convert string to lower case
		.if ([esi].dwFlags & CF_CASE)
			mov edi, [esi].pPtr
			mov edi, [edi]
			.while (dword ptr [edi])
				invoke _strlwr, dword ptr [edi]
				add edi, ebx
			.endw
		.endif
;----------------------------- sort string table
		.if ([esi].dwFlags & CF_SORT)
			mov edi, [esi].pPtr
			mov edi, [edi].SORTARRAY.pItems
			push edi
			xor ecx, ecx
			.while (dword ptr [edi])
				add edi, ebx
				inc ecx
			.endw
			pop edi
			mov edx, [esi].pPtr
			mov [edx].SORTARRAY.numItems, ecx
			invoke qsort, edi, ecx, ebx, offset cmpproc
		.endif
		add esi, sizeof CONVTABENTRY
	.endw
	ret
	assume esi:nothing

ConvertTables endp

PrintTable proc uses esi edi pTable:ptr LIST, pszFormatString:LPSTR
	mov esi, pTable
	xor edi, edi
	.if (esi)
		invoke Sort@List, esi
		invoke GetItem@List, esi, 0
		.while (eax)
			inc edi
			push eax
			invoke printf, pszFormatString, [eax].NAMEITEM.pszName,
				dword ptr [eax+4]
			pop ecx
			invoke GetItem@List, esi, ecx
		.endw
	.endif
	mov eax, edi
	ret
PrintTable endp

PrintSummary proc uses esi pszFileName:LPSTR

local	dwcntStruct:DWORD
local	dwcntMacro:DWORD
if ?PROTOSUMMARY
local	dwcntProto:DWORD
endif
if ?TYPEDEFSUMMARY
local	dwcntTypedef:DWORD
endif

	.if (g_bSummary)
		invoke printf, CStr(lf,"Summary %s:",lf), pszFileName
		invoke PrintTable, g_pStructures, CStr("structure: %s",lf)
		mov dwcntStruct, eax
		invoke printf, CStr(lf)
		invoke PrintTable, g_pMacros, CStr("macro: %s",lf)
		mov dwcntMacro, eax
if ?PROTOSUMMARY
		.if (g_bProtoSummary)
			invoke printf, CStr(lf)
			invoke PrintTable, g_pPrototypes, CStr("prototype: %s",lf)
			mov dwcntProto, eax
		.endif
endif
if ?TYPEDEFSUMMARY
		.if (g_bTypedefSummary)
			invoke printf, CStr(lf)
			invoke PrintTable, g_pTypedefs, CStr("typedef: %s",lf)
			mov dwcntTypedef, eax
		.endif
endif
if ?DYNPROTOQUALS
		.if (g_bUseDefProto)
			invoke printf, CStr(lf)
			invoke PrintTable, g_pQualifiers, CStr("prototype qualifier: %s [%X]",lf)
		.endif
endif
		invoke printf, CStr(lf,"%u structures",lf,"%u macros",lf),
			dwcntStruct, dwcntMacro
if ?PROTOSUMMARY
		.if (g_bProtoSummary)
			invoke printf, CStr("%u prototypes",lf), dwcntProto
		.endif
endif
if ?TYPEDEFSUMMARY
		.if (g_bTypedefSummary)
			invoke printf, CStr("%u typedefs",lf), dwcntTypedef
		.endif
endif
	.endif
	ret
PrintSummary endp

;--- process files

	option prologue:@sehprologue
	option epilogue:@sehepilogue

ProcessFiles proc pszFileSpec: ptr BYTE

local	hFFHandle:dword
local	pFilePart:LPSTR
local	szDir[MAX_PATH]:byte
local	szInpDir[MAX_PATH]:byte
local	szFileSpec[MAX_PATH]:byte
local	fd:WIN32_FIND_DATAA

	invoke GetCurrentDirectory, MAX_PATH, addr szDir
	invoke GetFullPathName, pszFileSpec, MAX_PATH, addr szFileSpec, addr pFilePart
	invoke _splitpath, addr szFileSpec, addr g_szDrive, addr g_szDir, addr g_szName, addr g_szExt
	invoke _makepath, addr szInpDir, addr g_szDrive, addr g_szDir, NULL, NULL
	dprintf <"ProcessFiles: input dir=%s",lf>, addr szInpDir
	invoke SetCurrentDirectory, addr szInpDir
	dprintf <"ProcessFiles: SetCurrentDirectory()=%X",lf>, eax
	invoke lstrcpy, addr szFileSpec, addr g_szName
	invoke lstrcat, addr szFileSpec, addr g_szExt

	dprintf <"ProcessFiles(%s)",lf>, addr szFileSpec

	invoke FindFirstFile, addr szFileSpec, addr fd
	.if (eax == -1)
		invoke printf, CStr("no matching files found",lf)
		jmp @exit
	.endif
	mov hFFHandle, eax
	.try
	.repeat
		.if (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)
			.if (word ptr fd.cFileName == '.')
				jmp skipitem
			.elseif ((word ptr fd.cFileName == '..') && (byte ptr fd.cFileName[2] == 0))
				jmp skipitem
			.endif
			.if (!g_bBatchmode)
				invoke printf, CStr("%s is a directory, process all files inside (y/n)?"), addr fd.cFileName
				.while (1)
					invoke _getch
					.if (al >= 'A')
						or al,20h
					.endif
					.break .if (al == 'y')
					.break .if (al == 'n')
					.break .if (al == 3)
				.endw
			.else
				mov al,'y'
			.endif
			push eax
			invoke printf, CStr(lf)
			pop eax
			.if (al == 3)
				jmp @exit2
			.elseif (al == 'y')
				invoke lstrcpy, addr szFileSpec, addr fd.cFileName
				invoke lstrcat, addr szFileSpec, CStr("\*.*")
				invoke ProcessFiles, addr szFileSpec
			.endif
			jmp skipitem
		.endif
		invoke ProcessFile, addr fd.cFileName, NULL
		xor al,1
		mov g_rc,eax
		invoke PrintSummary, addr fd.cFileName
;		invoke Destroy@List, g_pStructures
		mov g_pStructures, NULL
;		invoke Destroy@List, g_pMacros
		mov g_pMacros, NULL
if ?PROTOSUMMARY
;		invoke Destroy@List, g_pPrototypes
		mov g_pPrototypes, NULL
endif
if ?TYPEDEFSUMMARY
;		invoke Destroy@List, g_pTypedefs
		mov g_pTypedefs, NULL
endif
if ?DYNPROTOQUALS
;		invoke Destroy@List, g_pQualifiers
		mov g_pQualifiers, NULL
endif
		mov eax, g_pStringPool
		mov g_pStringPtr, eax
skipitem:
		.break .if (g_bTerminate)
		invoke FindNextFile, hFFHandle, addr fd
	.until (!eax)
@exit2:
	invoke FindClose, hFFHandle
	.exceptfilter
		mov eax,_exception_info()
		mov eax, [eax].EXCEPTION_POINTERS.ExceptionRecord
		mov ecx, [eax].EXCEPTION_RECORD.ExceptionCode
		.if (ecx == EXCEPTION_ACCESS_VIOLATION)
			mov ecx,[eax].EXCEPTION_RECORD.ExceptionInformation[1*4]
			mov eax,g_pStringPool
			mov edx,?STRINGPOOLMAX
			add edx,eax
			.if ((ecx >= eax) && (ecx < edx))
				and cx,0F000h
				invoke VirtualAlloc, ecx, ?STRINGPOOLSIZE, MEM_COMMIT, PAGE_READWRITE
				.if (eax)
					mov eax, EXCEPTION_CONTINUE_EXECUTION
					jmp exceptionfilter_done
				.endif
			.endif
		.endif
		mov eax, EXCEPTION_CONTINUE_SEARCH
exceptionfilter_done:
	.except
		invoke FindClose, hFFHandle
	.endtry
@exit:        
	invoke SetCurrentDirectory, addr szDir
	ret

ProcessFiles endp

	option prologue:prologuedef
	option epilogue:epiloguedef

;--- main
;--- reads profile file
;--- reads command line
;--- loops thru all header files calling ProcessFile

main proc c public argc:dword,argv:dword,envp:dword

local	dwSize:dword
local	pIniFile:dword
local	lpFilePart:LPSTR
local	szOutDir[MAX_PATH]:byte

	mov g_rc,1

;--- read h2incx.ini

	invoke ReadIniFile
	mov pIniFile, eax
	mov dwSize, edx
	invoke LoadTablesFromProfile, pIniFile, dwSize
	invoke ConvertTables

	mov ecx, 1
	mov ebx,argv
	.while (ecx < argc)
		push ecx
		invoke getoption, dword ptr [ebx+ecx*4]
		pop ecx
		jc main_er
		inc ecx
	.endw
	.if (!g_pszFilespec)
main_er:
		invoke printf, CStr("%s"), addr szUsage
		jmp @exit
	.endif
;--------------------- alloc string pool memory

	invoke VirtualAlloc, 0, ?STRINGPOOLMAX, MEM_RESERVE, PAGE_READWRITE
	.if (eax)
		mov g_pStringPool, eax
		mov g_pStringPtr, eax
		mov ecx, ?STRINGPOOLMAX
		add ecx, eax
		mov g_pStringPoolMax, ecx
		invoke VirtualAlloc, eax, ?STRINGPOOLSIZE * 4, MEM_COMMIT, PAGE_READWRITE
	.endif
	.if (!eax)
		invoke printf, CStr("fatal error: out of memory",lf)
		jmp @exit
	.endif
	.if (!g_pszOutDir)
		mov g_pszOutDir, CStr(".")
	.endif
	invoke GetFullPathName, g_pszOutDir, MAX_PATH, addr szOutDir, addr lpFilePart
	lea eax, szOutDir
	mov g_pszOutDir, eax

	invoke ProcessFiles, g_pszFilespec
@exit:
	.if (pIniFile)
		invoke VirtualFree, pIniFile, 0, MEM_RELEASE
	.endif
	.if (g_pStringPool)
		invoke VirtualFree, g_pStringPool, 0, MEM_RELEASE
	.endif
	mov eax, g_rc
	ret
main endp

	END
