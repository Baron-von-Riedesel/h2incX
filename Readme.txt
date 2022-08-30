
 1. About h2incX

 h2incX's purpose is to convert C header files to MASM include files.

 It was used to create the Win32/Win64 include files contained in WinInc.


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

 [Type Qualifier Conversion]
 *far=far


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


 5. License

 h2incX is Public Domain. Please read file license.txt for more details.

 Andreas Grech

