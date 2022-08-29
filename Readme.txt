
 1. About h2incX

 h2incX's purpose is to convert C header files to MASM include files.
 Once it is mature it should be able to convert the Win32 header files
 supplied by Microsoft (in the Platform SDK or in Visual C). This will
 never work 100% perfectly, though, some of the created includes will
 always require at least minor manual adjustments. 

 2. Installation/Deinstallation

 No installation procedure is supplied or required.
 File h2incX.exe is a Win32 PE binary and should run on all systems
 supporting this file format.
 File h2incXd.exe is a DOS binary. It is intended to be used on
 non-Win32 systems such as DOS, OS/2 or DOSEMU. A 80386 cpu is minimum.


 3. Usage

 h2incX is a console application and requires command line parameters:
 
     h2incX <options> filespec
   
 filespec specifies the files to process, usually C header files. Wildcards
 are allowed. 
 
 Case-sensitive options accepted by h2incX are:
 
 -a: this will add @align as alignment parameter for STRUCT/UNION 
     declarations. Initially equate @align is defined as empty string,
     but include files pshpackX.inc will change it. Thus this issue is
     handled roughly similiar as with Microsoft VC. Set this option if
     you want to ensure VC compatibility.
     
 -b: batch mode without user interaction. 
 
 -c: copy comments found in source files to the created .INC files
 
 -dn: define handling of __declspec(dllimport).
   n=0: this is the default behaviour. Depending on values found in
        h2incX.ini, section [Prototype Qualifiers], h2incX will create
        either true MASM prototypes or externdefs referencing IAT entries,
        which is slightly faster.
   n=1: always assume __declspec(dllimport) for prototypes. This will force
        h2incX to always create externdefs referencing IAT entries.
   n=2: always ignore __declspec(dllimport) for prototypes. This will force
        h2incX to always create true MASM prototypes.
   n=3: use @DefProto macro to define prototypes. This may reduce file size
        compared to option -d0 or -d1 and makes the generated includes more
        readable, but more importantly it will allow to link statically or
        dynamically with one include file version and still use the fastest
        calling mechanism for both methods. Example:
     
          _CRTIMP char * __cdecl _strupr( char *);
     
        With option -d0 this would be converted to either:
     
          proto__strupr typedef proto c  :ptr sbyte
          externdef c _imp___strupr: ptr proto__strupr
          _strupr equ <_imp___strupr>

        or, if entry _CRTIMP=8 is *not* included in h2incX.ini:
     
          _strupr proto c :ptr sbyte

        With option -d3 h2incX will instead generate:

          @DefProto _CRTIMP, _strupr, c, <:ptr sbyte>, 4

        and @DefProto macro will then create either a IAT based externdef
        or a true prototype depending on the current value of _CRTIMP.
         
 -e: write full decorated names of function prototypes to a .DEF file,
     which may then be used as input for an external tool to create import
     libraries (POLIB for example).
     
 -i: process includes. This option will cause h2incX to process all
     #include preprocessor lines in the source file. So if you enter
     "h2incX -i windows.h" windows.h and all headers referenced inside
     windows.h will be converted to include files! Furthermore, h2incX
     will store all structure and macro names found in any source file
     in one symbol table.
 
 -I directory: specify an additional directory to search for header files.
     May be useful in conjunction with -i switch.
     
 -o directory: set output directory. Without this option output files are
     created in the current directory.
     
 -p: add prototypes to summary (-S).
     
 -q: avoid RECORD definitions. Since names in records must be unique in MASM
     it may be conveniant to avoid records at all. Instead equates will be
     defined.
 
 -r: size-safe RECORD definitions. May be required if a C bitfield isn't
     fully defined, that is, only some bits are declared. With this option
     set the record is enclosed in a union together with its type.
     example (excerpt from structure MENUBARINFO in winuser.h):
     
         BOOL  fBarFocused:1;
         BOOL  fFocused:1;
         
     is now translated to:    
     
         MENUBARINFO_R0	RECORD fBarFocused:1,fFocused:1
         union                 ;added by -r switch	
             BOOL ?            ;added by -r switch
             MENUBARINFO_R0 <>
         ends                  ;added by -r switch
         
     So MASM will reserve space for a BOOL (which is 4 bytes). Without
     the -r option MASM would pack the bits in 1 byte only.
     
 -s c|p|t|e: selective output. Without this option everything is generated.
     Else select c/onstants or p/rototypes or t/ypedefs or e/xternals
     or any combination of these.
     
 -S: display summary of structures, macros, prototypes (optionally, -p) and
     typedefs (optionally, -t) found in source.
 
 -t: add typedefs to summary (-S).
 
 -u: generate untyped parameters in prototypes. Without this option the
     types are copied from the source file.
     
 -v: verbose mode. h2incX will display the files it is currently processing.

 -Wn: set warning level:
     n=0: display no warnings
     n=1: display warnings concerning usage of reserved words as names
          of structures, prototypes, typedefs or equates/macros.
     n=2: display warnings concerning usage of reserved words as names
          of structure members or macro parameters.
     n=3: display all warnings.
     
 -y: overwrites existing .INC files without confirmation. Without this
     option h2incX will not process input files if the resulting output
     file already exists. Shouldn't be used in conjunction with -i option
     to avoid multiple processing of the same header file.
     
 h2incX expects a private profile file with name h2incX.INI in the directory
 where the binary is located. This file contains some parameters for fine
 tuning. For more details view this file.


 Some examples for how to use h2incX:
 
  þ h2incX c:\c\include\windows.h
  
    will process c:\c\include\windows.h and generate a file windows.inc
    in the current directory.
    
  þ h2incX -i c:\c\include\windows.h

    will process c:\vc\include\windows.h and all include files referenced
    by it. Include files will be stored in current directory.

  þ h2incX c:\c\include    or    h2incX c:\c\include\*.*

    will process all files in c:\c\include. Include files will be stored
    in current directory.

  þ h2incX -o c:\temp *.h

    will process all files with extension .h in current directory and store
    the include files in c:\temp.


 Due to its origin, h2incX assumes C integers are 32-bit. To convert
 16-bit C headers one will have to slightly adjust h2incX.ini:
 
 [Type Conversion 1]
 enum=WORD
 INT=WORD
 int=WORD

 [Type Conversion 2]
 int=SWORD
 unsigned int=WORD

 
 4. Known Bugs and Restrictions

 - one should be aware that some C header file declarations simply cannot
   be translated to ASM. There are no things like inline functions in ASM,
   for example.
 - on some situations h2incX has to "count" braces. This can interfere
   with #if preprocessor commands, because h2incX cannot evaluate expressions
   in these commands. As a result h2incX may get confused and produce garbage.
 - h2incX knows little about C++ classes. Source files which have class 
   definitions included may confuse h2incX.
 - "far" and "near" qualifiers are skipped, so this tool will not work
   for 16bit includes.
 - macros in C header files will most likely not be converted reliably
   and therefore may require manual adjustments.


 5. History

 01/05: V0.80: first pre-release
 01/05: V0.81: prototypes with qualifier __declspec(dllimport) will use
               IAT now (call dword ptr [_imp__xxx]).
 01/05: V0.82: some bugfixes
 01/05: V0.83: more bugfixes
 01/05: V0.84: fixed a memory allocation error
 01/05: V0.85: bit fields without names supported
 01/05: V0.86: size-safe bitfields with -r option
 01/05: V0.87: h2incXd was linked wrong. bitfields created wrong
 01/05: V0.88: [alignment] section added to h2incX.ini
 01/05: V0.89: adding structures to section [structure names] now only
               required for externally defined structures.
 01/05: V0.90: [Known Macros] in h2incX.ini changed to string pairs!
               Added new cmdline switch -i (old -i renamed to -y!) for
               nested processing of header files.
 01/05: V0.91: -I option added.
               -S option added.
               h2incX remembers macros defined in the source, so only
               external macros have to be added to [Known Macros] section
 01/05: V0.92: "enum {}" (without typedef) now converted (VARENUM in wtypes.h)
 01/05: V0.93: "COM" includes can be translated now, at least the C syntax
               part. bugfix: macro invokations in EQU lines sometimes lost
               their braces. A simple GUI sample (sample2) added. -e option
               added.
 01/05: V0.94: MIDL generated macros for virtual function access in C
               (COBJMACROS) are now converted to MASM macros.
               COM server sample (simplestserver) added.
               Function pointers as parameters in (virtual) function pointer
               declarations now handled correctly (method IViewObject::Draw
               in oleidl.h). DirectDraw sample added.
 01/05: V0.95: bugfix: '/' in source may have been interpreted as begin of
               a comment. Method names in STDMETHOD macro checked for reserved
               words. C++ reserved words 'public', 'private', 'operator' and
               'friend' now tolerated.
 01/05: V0.96: bugfix: expressions in enums may have been interpreted as
               function pointers. bugfix: floating point constants now 
               recognized. D3D includes added.
 01/05: V0.97: no more invalid typedefs when translating "forward"
               declarations of MIDL generated includes. Binary searches
               are used now, so h2incX will run faster for large header files.
 01/05: V0.98: bugfix: externdefs were created wrong in version 0.97!
               bugfix: missing includes for simplestserver sample added.
               translated OLECTL.INC and OCIDL.INC added to Include subdir.
 01/05: V0.99: bugfix: VARIANT in OAIDL.INC defined wrong.
 01/05: V0.99.1: (U)LARGE_INTEGER definitions in winnt.h now handled correctly
               bugfix: preprocessor commands now recognized when there are 
               spaces between '#' and the command.
 01/05: V0.99.2: bugfix: enums without name ("enum {...};") caused an access
               violation. bugfix: h2incX didn't recognize end of a comment if
               comment had pattern "/* ... /* ... */". COMMCTRL.INC, 
               WININET.INC and RICHEDIT.INC added to Include subdir.
 02/05: V0.99.3: Handling of string literals improved.
               bugfix: STDMETHOD parameters on succeeding lines were skipped.
               Win32 includes and samples now supplied in an own package at
               http://www.japheth.de/Download/win32inc.zip.
 02/05: V0.99.4: bugfix: some structure names added to [Alignment] section in
               h2incX.ini. Cmdline option -p added.
               bugfix: __declspec(...) now analyzed correctly
 02/05: V0.99.5: Cmdline option -t added.
               bugfix: function pointers as function parameters in prototypes
               now recog
 02/05: V0.99.6: now less equates defined as text literals (<>). Nameless
               structure members in structures recognized. Structures without
               names ["typedef struct {...} * pStructPtr"] now handled 
               correctly.
 02/05: V0.99.7: keyword "class" now accepted. Some very preliminary C++ name
               decorating code added (VC).
 02/05: V0.99.8: cmdline switch -Wn added (so switch -e could be deleted).
               bugfix: empty continuation lines weren't recognized.
               bugfix: pointer types were added to structure symbol table
 02/05: V0.99.9: Warning displayed (-W1) if macro/equate is a reserved word.
               Warning displayed (-W2) if macro parameter is a reserved word.
               Rudimentary support for virtual base classes and virtual 
               function tables. Keyword 'static' recognized.
 02/05: V0.99.10: bugfix: NOT is invalid in if/elseif expressions, replaced
               by "0 eq". cmdline switch -d extended, makes switch -g 
               superfluous. Optionally declaring prototypes with @DefProto
               macro added. "#pragma message()" now converted to %echo, and
               "#error" converted to .err.
 02/05: V0.99.11: bugfix: declaration "struct tagname membername;" in
               structures was converted wrong (winsock.h, sin_addr).
 02/05: V0.99.12: bugfix: bugfix of V0.99.11 wasn't satisfactory, in fact
               introduced another, severe bug.
 02/05: V0.99.13: interface vtable entries of MIDL created header files now
               described with STDMETHOD macro, thus reducing size and
               increasing readability of INC file. 
 02/05: V0.99.14: bugfix: COBJMACROS for interface names beginning with "_" 
               didn't work (ADOINT.H)
 09/05: V0.99.15: some bugfixes
 09/05: V0.99.16: version 0.99.15 wrote the output file in the directory of
               the input files if option -o was omitted.
 01/06: V0.99.17: cmdline switches used when h2incX was launched now copied
               to the include file header.
 07/06: V0.99.18: -e cmdline option added.
 04/07: V0.99.19: copyright message adjusted so it is more clear that
               the copyright is not intended for the created include file.
               message "no items for .DEF file" now is only displayed if
               warning level is > 2.
 03/09: V0.99.20: DOS version now created using HX's DOS-PE feature, it's
               a stand-alone binary. Syntax
                 typedef <simple_type> <new_type>[elements];
               now converted to a structure instead of a typedef.
 08/22: V0.99.21: WinInc dependency removed, now just needs HX.


 6. License

 h2incX is Public Domain. Please read file license.txt for more details.

 Andreas Grech

