
;-------------- equates

;--- ascii codes

tab	equ 9
lf	equ 10
cr	equ 13

ifndef LPSTR
LPSTR typedef ptr SBYTE
endif
ifndef BOOLEAN
BOOLEAN typedef BYTE
endif

?VERSION		equ "v0.99.21"
?COPYRIGHT		equ "Public Domain, written by Andreas Grech"
?PROTOSUMMARY	equ 1		;list prototypes in summary
?TYPEDEFSUMMARY	equ 1		;list typedefs in summary
?DYNPROTOQUALS	equ 1		;1=proto qualifiers in dynamic table

;--- prototype qualifier equates

FQ_CDECL	equ 01h ;__cdecl
FQ_STDCALL	equ 02h ;__stdcall
FQ_INLINE	equ 04h ;__inline
FQ_IMPORT	equ 08h ;__declspec(dllimport)
FQ_SYSCALL	equ 10h ;__syscall
FQ_PASCAL	equ 20h ;__pascal
FQ_STATIC	equ 100h;static	

;-------------- typedefs + structures

SORTARRAY	struct
pItems		DWORD ?
numItems	DWORD ?
SORTARRAY	ends

;--- name item. structures or macros declared in headers
;--- are saved in a list so h2incx can decide if
;--- a type is a structure or not (? vs <>)

NAMEITEM struct
pszName	LPSTR ?		;ptr to item name
NAMEITEM ends

;-------------- prototypes + externdefs

_strcmp		proto stdcall :ptr byte, :ptr byte
_malloc		proto stdcall :DWORD
_free		proto stdcall :ptr
cmpproc		proto c :ptr ,:ptr
AddString	proto stdcall pszString:LPSTR, dwValue:DWORD

externdef g_szDrive:BYTE
externdef g_szDir:BYTE
externdef g_szName:BYTE
externdef g_szExt:BYTE

externdef g_pszIncDir:LPSTR
externdef g_dwStructSuffix:DWORD
externdef g_dwDefCallConv:DWORD
externdef g_pStructures:DWORD
externdef g_pMacros:DWORD
if ?PROTOSUMMARY
externdef g_pPrototypes:DWORD
endif
if ?TYPEDEFSUMMARY
externdef g_pTypedefs:DWORD
endif
externdef g_pQualifiers:DWORD
externdef g_ReservedWords:SORTARRAY
externdef g_KnownStructures:SORTARRAY
externdef g_ProtoQualifiers:SORTARRAY
externdef g_ppSimpleTypes:DWORD
externdef g_ppKnownMacros:DWORD
externdef g_ppTypeAttrConv:DWORD
externdef g_ppConvertTokens:DWORD
externdef g_ppConvertTypes1:DWORD
externdef g_ppConvertTypes2:DWORD
externdef g_ppConvertTypes3:DWORD
externdef g_ppAlignments:DWORD
externdef g_ppTypeSize:DWORD

externdef g_bTerminate:BYTE

externdef g_bAddAlign:BYTE
externdef g_bBatchmode:BYTE
externdef g_bUseDefProto:BYTE
externdef g_bIncludeComments:BYTE
externdef g_bAssumeDllImport:BYTE
;externdef g_bSuppressExists:BYTE
externdef g_bIgnoreDllImport:BYTE
externdef g_bProcessInclude:BYTE
externdef g_bUntypedMembers:BYTE
externdef g_bProtoSummary:BYTE
externdef g_bNoRecords:BYTE
externdef g_bRecordsInUnions:BYTE
externdef g_bSummary:BYTE
externdef g_bTypedefSummary:BYTE
externdef g_bUntypedParams:BYTE
externdef g_bVerbose:BYTE
externdef g_bWarningLevel:BYTE
externdef g_bOverwrite:BYTE
externdef g_bCreateDefs:BYTE

externdef g_bPrototypes:BYTE
externdef g_bTypedefs:BYTE
externdef g_bConstants:BYTE
externdef g_bExternals:BYTE

;--- debug printf macro

dprintf macro x:req, y:vararg
ifdef _TRACE
	pushad
  ifnb <y>
	invoke printf, CStr(<x>), y
  else
	invoke printf, CStr(<x>)
  endif
	popad
endif
	endm

