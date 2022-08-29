
;--- LIST structure. is just a table of items

LIST	struct
ifdef IMPL_LIST
pFree	dd ?	;next free item in this block
pMax	dd ?	;end of this list block
dwSize	dd ?	;size of 1 item in list
endif
LIST	ends


Create@List		proto stdcall :DWORD, :DWORD
Destroy@List	proto stdcall :ptr LIST
Sort@List		proto stdcall :ptr LIST
SortCS@List		proto stdcall :ptr LIST
AddItem@List	proto stdcall :ptr LIST, pszName:LPSTR
AddItemArray@List proto stdcall :ptr LIST, pItem:ptr NAMEITEM, dwItems:DWORD
GetItem@List	proto stdcall :ptr LIST, pItem:ptr NAMEITEM
FindItem@List	proto stdcall :ptr LIST, pszName:LPSTR
GetItemSize@List proto stdcall :ptr LIST
GetNumItems@List proto stdcall :ptr LIST

FNCOMPARE typedef proto c :ptr, :ptr
LPFNCOMPARE typedef ptr FNCOMPARE
_bsearch		proto stdcall :ptr, :ptr, :DWORD, :DWORD, :LPFNCOMPARE

