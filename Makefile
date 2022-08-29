
# nmake makefile, creates h2incX.exe (Win32) and h2incXd.exe (DOS)
# tools used:
# - JWasm or MASM 6.x
# - JWlink
# - HXDEV ( Win32 import libs, CRT )

name = h2incX

WIN=1
DOS=1
HX=\hx

!ifndef DEBUG
DEBUG=0
!endif

!if $(DEBUG)
OUTDIR=Debug
!else
OUTDIR=Release
!endif

!if $(DEBUG)
AOPTD=-Zi -D_DEBUG -D_TRACE
LOPTD= debug c
LINK= jwlink.exe
!else
LOPTD=
AOPTD=
LINK= jwlink.exe
!endif

!ifndef MASM
MASM=0
!endif

AOPT=-c -nologo -coff -Sg -Fl$(OUTDIR)\ -Fo$(OUTDIR)\ $(AOPTD) -IInclude -I$(HX)\Include
!if $(MASM)
ASM = ml.exe $(AOPT)
!else
ASM = jwasm.exe $(AOPT)
!endif

OBJS = $(OUTDIR)\$(name).obj  $(OUTDIR)\CIncFile.obj $(OUTDIR)\CList.obj

!if $(WIN)
TARGETW=$(OUTDIR)\$(name).exe
LIBSW=libc32s.lib Lib\except.lib dkrnl32.lib
!endif
!if $(DOS)
TARGETD=$(OUTDIR)\$(name)d.exe
LIBSD=libc32s.lib Lib\except.lib imphlp.lib dkrnl32s.lib
!endif

.asm{$(OUTDIR)}.obj:
	@$(ASM) $<

ALL: $(OUTDIR) $(TARGETW) $(TARGETD)

$(OUTDIR):
	@mkdir $(OUTDIR)

$(OUTDIR)\$(name).exe: $(OBJS) Makefile
#	@link /SUBSYSTEM:CONSOLE $(OBJS) /OUT:$(OUTDIR)\$(name).exe $(LIBSW) /LIBPATH:$(HX)\Lib /map:$*.map
	@jwlink $(LOPTD) format win pe f {$(OBJS)} n $(OUTDIR)\$(name).exe libpath $(HX)\Lib lib {$(LIBSW)} op q,m=$*.map,start=_mainCRTStartup

$(OUTDIR)\$(name)d.exe: $(OBJS) Makefile
#	@link /SUBSYSTEM:CONSOLE $(HX)\Lib\InitW32.obj $(OBJS) /OUT:$(OUTDIR)\$(name)d.exe /libpath:$(HX)\Lib $(LIBSD) /stub:$(HX)\Bin\loadpex.bin /map:$*.map /fixed:no
	@jwlink $(LOPTD) format win pe hx f {$(HX)\Lib\InitW32.obj $(OBJS)} n $(OUTDIR)\$(name)d.exe libpath $(HX)\Lib lib {$(LIBSD)} op q,stub=$(HX)\Bin\loadpex.bin,m=$*.map

$(OUTDIR)\$(name).obj: $(name).inc CIncFile.inc

$(OUTDIR)\CIncFile.obj: $(name).inc CIncFile.inc

$(OUTDIR)\CList.obj: $(name).inc CList.inc

clean:
	@del $(OUTDIR)\*.obj
	@del $(OUTDIR)\*.map
	@del $(OUTDIR)\*.lst
	@del $(OUTDIR)\*.exe
