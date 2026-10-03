$! VMS_CCSERVER.COM - compile server for the host-side configure run (tools/vmscc)
$!
$! P1 = directory to serve (requests arrive there by sftp)
$! P2 = C compiler qualifiers
$! P3 = optional NAME=directory: define NAME as a rooted logical for that
$!      directory (e.g. NAME$ROOT=dev:[dir.SUB])
$!
$! Protocol, per test program <id>:
$!   host puts  <id>.C   - the source
$!   host puts  <id>.REQ - compile | link | preprocess, optionally followed
$!                         by a line of include directories and a line of
$!                         object libraries (comma-separated)
$!   server writes <id>.LOG (compiler/linker messages), <id>.I (preprocess),
$!   then <id>.RES last: one line "ok" or "fail".
$! The host deletes the request files after collecting the result.
$! Create CCSERVER.STOP in P1 to stop; it also stops after ~30 minutes idle.
$!
$ set noon
$ set default 'p1'
$ ccq = p2
$ if p3 .nes. ""
$ then
$   lname = f$element(0, "=", p3)
$   ldir = f$element(1, "=", p3)
$   ldev = f$parse(ldir,,,"DEVICE","NO_CONCEAL")
$   lroot = f$parse(ldir,,,"DIRECTORY","NO_CONCEAL") - "][" - "]" + ".]"
$   define/process/translation_attributes=concealed 'lname' 'ldev''lroot'
$   write sys$output "ccserver: ", lname, " = ", ldev, lroot
$ endif
$ if f$search("CCSERVER.STOP") .nes. "" then delete/nolog CCSERVER.STOP;*
$ write sys$output "ccserver: serving ", f$environment("DEFAULT"), " with ", ccq
$ idle = 0
$loop:
$ if f$search("CCSERVER.STOP") .nes. "" then goto quit
$ req = f$search("*.REQ", 7)
$ if req .eqs. ""
$ then
$   wait 0:0:0.25
$   idle = idle + 1
$   if idle .gt. 7200 then goto quit
$   goto loop
$ endif
$ idle = 0
$ id = f$parse(req,,,"NAME")
$ incs = ""
$ libs = ""
$ open/read/error=loop r 'req'
$ read/end=badreq r mode
$ read/end=badreq r incs
$ read/end=badreq r libs
$badreq:
$ close r
$ incq = ""
$ if incs .nes. "" then incq = "/INCLUDE_DIRECTORY=(''incs')"
$ libq = ""
$ if libs .nes. "" then libq = "," + libs + "/LIBRARY"   ! one library
$ if f$search("''id'.LOG") .nes. "" then delete/nolog 'id'.LOG;*
$ define/user sys$output 'id'.LOG
$ define/user sys$error 'id'.LOG
$ if mode .eqs. "preprocess"
$ then
$   cc 'ccq''incq' /nolist/noobject/preprocess_only='id'.I 'id'.C
$ else
$   cc 'ccq''incq' /nolist/object='id'.OBJ 'id'.C
$ endif
$ sev = $severity
$ ok = (sev .ne. 2) .and. (sev .ne. 4)
$ if ok .and. mode .eqs. "link"
$ then
$   define/user sys$output 'id'.LLOG
$   define/user sys$error 'id'.LLOG
$   link/nomap/executable='id'.EXE 'id'.OBJ'libq'
$   ok = $severity .eq. 1
$   if f$search("''id'.LLOG") .nes. ""
$   then
$     append/new_version 'id'.LLOG 'id'.LOG
$     delete/nolog 'id'.LLOG;*
$   endif
$ endif
$ open/write o 'id'.TRS
$ if ok
$ then write o "ok"
$ else write o "fail"
$ endif
$ close o
$ rename 'id'.TRS 'id'.RES
$ delete/nolog 'req'
$ if f$search("''id'.OBJ") .nes. "" then delete/nolog 'id'.OBJ;*
$ if f$search("''id'.EXE") .nes. "" then delete/nolog 'id'.EXE;*
$ goto loop
$quit:
$ if f$search("CCSERVER.STOP") .nes. "" then delete/nolog CCSERVER.STOP;*
$ write sys$output "ccserver: stopping"
