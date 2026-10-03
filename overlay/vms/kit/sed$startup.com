$! SED$STARTUP.COM - system startup for GNU sed on OpenVMS
$!
$! Installed by PCSI into SYS$STARTUP.  Defines the system logical name
$! SED$ROOT, pointing at the installed [SED] directory.  To run it at every
$! boot, add this line to SYS$MANAGER:SYSTARTUP_VMS.COM:
$!
$!     $ @SYS$STARTUP:SED$STARTUP.COM
$!
$! P1 = "INSTALL": also print the post-installation tasks (PCSI runs it so).
$! P1 = "REMOVE":  deassign SED$ROOT instead (PCSI runs it so at removal).
$!
$! Users then define the sed command with
$!     $ @SED$ROOT:[000000]SED$SETUP.COM
$!
$ set noon
$ mode = f$edit(p1, "UPCASE")
$ if mode .eqs. "REMOVE"
$ then
$   if f$trnlnm("SED$ROOT", "LNM$SYSTEM_TABLE") .nes. "" then -
        deassign/system/executive_mode SED$ROOT
$   exit 1
$ endif
$!
$! This procedure sits in <destination>[SYS$STARTUP]; the product is in
$! <destination>[SED].  Rooted logicals need the physical form:
$! DKA0:[SYS0.SYSCOMMON.SYS$STARTUP] -> DKA0:[SYS0.SYSCOMMON.SED.]
$ proc = f$environment("PROCEDURE")
$ dev = f$parse(proc,,,"DEVICE","NO_CONCEAL")
$ dir = f$edit(f$parse(proc,,,"DIRECTORY","NO_CONCEAL"), "UPCASE") - "]["
$ root = dir - "SYS$STARTUP]" + "SED.]"
$ if root .eqs. dir + "SED.]"
$ then
$   write sys$error "SED$STARTUP: expected to be in a [SYS$STARTUP] directory, not ''dir'"
$   exit 44
$ endif
$ root = root - ".000000"
$ define/system/executive_mode/translation_attributes=concealed SED$ROOT 'dev''root'
$ if f$search("SED$ROOT:[BIN]SED.EXE") .eqs. ""
$ then
$   write sys$error "SED$STARTUP: SED.EXE not found under ''dev'''root'"
$   exit 44
$ endif
$ if mode .nes. "INSTALL" then exit 1
$ say = "write sys$output"
$ say ""
$ say "    Post-installation tasks for GNU sed"
$ say ""
$ say "    At system startup: to define SED$ROOT at every boot, add this line to"
$ say "    SYS$MANAGER:SYSTARTUP_VMS.COM:"
$ say "    $ @SYS$STARTUP:SED$STARTUP.COM"
$ say "    For each user: to define the sed command, add this line to LOGIN.COM:"
$ say "    $ @SED$ROOT:[000000]SED$SETUP.COM"
$ say ""
$ say "    PRODUCT REMOVE SED removes the product and deassigns SED$ROOT."
$ say ""
$ exit 1
