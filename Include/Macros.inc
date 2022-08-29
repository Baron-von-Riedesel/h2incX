
;--- CStr() define a string in .CONST
;--- or in .CONST$2 if .CONST is the current section

CStr macro text:VARARG
local sym
ifidni @CurSeg,<CONST>
CONST$2 segment FLAT public 'CONST'
else
CONST segment FLAT public 'CONST'
endif
ifidni <text>,<"">
  sym db 0
else
  sym db text,0
endif
@CurSeg ends
	exitm <offset sym>
	endm

