
;--- implements LIST class
;--- a "list" in this context is a simple array with fixed size.
;--- the list is always sorted, so a binary search can be used.
;--- A list item always begins with a string pointer (NAMEITEM)

	.386
	.model flat, stdcall
	option casemap:none

	.nolist
	.nocref
	include winbase.inc
	include stdlib.inc
	include macros.inc
	.list
	.cref
	include h2incX.inc
IMPL_LIST equ <>
	include CList.inc

?BINARYSEARCH equ 1		;use binary search to find items

GetNumItems macro pList       
	lea ecx, [pList+sizeof LIST]
	mov eax, [pList].LIST.pFree
	sub eax, ecx
	cdq
	div [pList].LIST.dwSize
	endm

	.code

if ?BINARYSEARCH

;--- unlike the standard CRT bsearch this bsearch returns
;--- in EDX the first item > key

_bsearch PROC uses esi key:ptr, base:ptr, num:DWORD, width_:DWORD, compare:LPFNCOMPARE

local	half:dword
local	mid:dword
local	hi:dword
local	lo:dword

;--------------------------- set lo and hi
	mov ecx, base
	mov eax, num
	dec eax
	imul eax, width_
	add eax, ecx
	mov lo, ecx
	mov hi, eax
	mov esi, -1
nextloop:			;<---
	mov eax, lo
	cmp eax, hi
	ja notfound
;--------------------------- set mid
	mov ecx, num
	shr ecx, 1
	mov half, ecx
	and ecx, ecx
	je done				;half is 0, done
	mov eax, ecx
	mov edx, num
	test dl, 1
	jne @F
	dec eax
@@:
	imul eax, width_
	add eax, lo
	mov mid, eax

;--------------------------- compare
	invoke  compare, key, mid
	mov esi, eax
	cmp eax, 0
	je found
	jg isgreater
	mov eax, mid		;continue search with the lower half
	sub eax, width_		;set new hi
	mov hi, eax
	mov eax, half		;set new num
	mov ecx, num
	test cl,1
	jnz @F
	dec eax
@@:
	mov num, eax
	jmp nextloop

isgreater:				;continue search with the upper half
	mov edx, mid		;set new lo
	add edx, width_
	mov lo, edx
	mov eax, half		;set new num
	mov num, eax
	jmp nextloop

done:
	cmp num, 0
	je notfound
	invoke compare, key, lo
	mov esi, eax
	neg eax
	sbb eax, eax
	not eax
	and eax, lo
	jmp @exit
found:
	mov eax, mid
	jmp @exit
notfound:
	xor eax, eax		;not found
@exit:
	mov edx, lo
	cmp esi, 0
	jl @F
	add edx, width_
@@:
	ret
_bsearch ENDP

endif

;--- constructor

Create@List proc dwNumItems:DWORD, dwItemSize:DWORD
	mov eax, dwNumItems
	mov ecx, dwItemSize
	imul eax, ecx
	add eax, sizeof LIST
	push eax
	invoke _malloc, eax
	pop edx
	.if (eax)
		lea ecx, [eax+sizeof LIST]
		lea edx, [eax+edx]
		mov [eax].LIST.pFree,ecx
		mov [eax].LIST.pMax,edx
		mov ecx, dwItemSize
		mov [eax].LIST.dwSize, ecx
	.endif
	ret
Create@List endp

;--- destructor

Destroy@List proc pList:ptr LIST
	.if (pList)
		invoke _free, pList
	.endif
	ret
Destroy@List endp

cmpproc2 proc c private p1:ptr NAMEITEM, p2:ptr NAMEITEM
	mov ecx, p1
	mov edx, p2
	invoke _strcmp, [ecx].NAMEITEM.pszName, [edx].NAMEITEM.pszName
	ret
cmpproc2 endp

;--- add an item in a list
;--- return: eax=inserted item or NULL

AddItem@List proc uses esi pList:ptr LIST, pItem:LPSTR

if ?BINARYSEARCH
local	tmpitem:NAMEITEM
endif

	mov esi,pList
	mov eax,[esi].LIST.pFree
	.if (eax == [esi].LIST.pMax)
		xor eax, eax
		jmp @exit
	.endif
if ?BINARYSEARCH
	mov edx, pItem
	mov tmpitem.pszName, edx
	GetNumItems esi
	invoke _bsearch, addr tmpitem, addr [esi+sizeof LIST], eax, [esi].LIST.dwSize, cmpproc2
	.if (!eax)
		mov eax, edx
	.endif
;----------------------- make room for the new item        
	pushad
if 0;ifdef _DEBUG
	mov ecx, eax
	lea edx, [esi + sizeof LIST]
	sub ecx, edx
	shr ecx, 2
	dprintf <"AddListItem %u [%s]",10>, ecx, pItem
endif
	mov edi, [esi].LIST.pFree
	mov ecx, [esi].LIST.dwSize
	sub ecx, 4
	lea esi, [edi-4]
	add edi, ecx
	lea ecx, [esi+4]
	sub ecx, eax
	shr ecx, 2
	std
	rep movsd
	cld
	popad
endif
	mov edx, pItem
	mov [eax].NAMEITEM.pszName, edx
	mov ecx, [esi].LIST.dwSize
	add [esi].LIST.pFree, ecx
@exit:
	ret
AddItem@List endp

;--- add an array of - already sorted! - items to a list

AddItemArray@List proc pList:ptr LIST, pItems:ptr NAMEITEM, dwNum:DWORD
	pushad
	mov esi,pList
	mov ecx, dwNum
	imul ecx, [esi].LIST.dwSize
	mov edi, [esi].LIST.pFree
	lea eax, [edi+ecx]
	.if (eax >= [esi].LIST.pMax)
		xor eax, eax
		jmp @exit
	.endif
	push esi
	mov esi, pItems
	shr ecx, 2
	rep movsd
	pop esi
	mov [esi].LIST.pFree, edi
@exit:
	popad
	ret
AddItemArray@List endp

;--- get an item in a list

GetItem@List proc pList:ptr LIST, pPrevItem:ptr NAMEITEM

	mov ecx, pList
	mov eax, pPrevItem
	.if (eax)
		add eax,[ecx].LIST.dwSize
	.else
		lea eax,[ecx+sizeof LIST]
	.endif
	.if (eax >= [ecx].LIST.pFree)
		xor eax, eax
	.endif
	ret

GetItem@List endp

;--- find an item in a list

FindItem@List proc uses esi pList:ptr LIST, pszName:LPSTR

if ?BINARYSEARCH
local	tmpitem:NAMEITEM
endif

	mov esi, pList
	.if (esi)
if ?BINARYSEARCH
		mov edx, pszName
		mov tmpitem.pszName, edx
		GetNumItems esi
		invoke _bsearch, addr tmpitem, addr [esi+sizeof LIST], eax, [esi].LIST.dwSize, cmpproc2
		ret
else
		invoke GetListItem, esi, 0
		.while (eax)
			push eax
			invoke _strcmp, pszName, [eax].NAMEITEM.pszName
			pop ecx
			.if (!eax)
				mov eax, ecx
				ret
			.endif
			invoke GetListItem, esi, ecx
		.endw
endif
	.endif
	xor eax, eax
	ret
FindItem@List endp

cmpproc proc c private p1:ptr, p2:ptr
	mov ecx, p1
	mov edx, p2
	invoke lstrcmpi, [ecx].NAMEITEM.pszName, [edx].NAMEITEM.pszName
	ret
cmpproc endp

Sort@List proc uses esi pList:ptr LIST
	mov esi, pList
	GetNumItems esi
	invoke qsort, addr [esi+sizeof LIST], eax, [esi].LIST.dwSize, offset cmpproc
	ret
Sort@List endp

;--- sort case sensitive

SortCS@List proc uses esi pList:ptr LIST
	mov esi, pList
	GetNumItems esi
	invoke qsort, addr [esi+sizeof LIST], eax, [esi].LIST.dwSize, offset cmpproc2
	ret
SortCS@List endp

GetItemSize@List proc pList:ptr LIST
	mov ecx, pList
	mov eax, [ecx].LIST.dwSize
	ret
GetItemSize@List endp

GetNumItems@List proc uses esi pList:ptr LIST
	mov esi, pList
	GetNumItems esi
	ret
GetNumItems@List endp

	end
