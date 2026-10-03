$! GNV_ENV.COM - define GNV's root logical names for this process only.
$!
$! GNV's own GNV$STARTUP.COM defines GNU and SYS$POSIX_ROOT system-wide.
$! Where it has not been run, this gives the current process the same view
$! without changing anything system-wide.  Defines the symbol BASH.
$!
$! The x86-64 kit is rooted one level down, at [GNV.X86].
$ root = ""
$ if f$search("SYS$COMMON:[GNV]BIN.DIR") .nes. "" then root = "SYS$COMMON:[GNV]"
$ if f$search("SYS$COMMON:[GNV.X86]BIN.DIR") .nes. "" then root = "SYS$COMMON:[GNV.X86]"
$ if root .eqs. ""
$ then
$   write sys$error "GNV_ENV: GNV not found under SYS$COMMON:[GNV]"
$   exit 44
$ endif
$! Rooted logicals need a physical device and directory: DKA0:[SYS0.SYSCOMMON.GNV.]
$ phys = f$parse(root,,,"DEVICE","NO_CONCEAL") + f$parse(root,,,"DIRECTORY","NO_CONCEAL")
$ phys = phys - "][" - "]" + ".]"
$ phys = phys - ".000000"
$ if f$trnlnm("GNU") .eqs. "" then define/process/translation=concealed GNU 'phys'
$ if f$trnlnm("SYS$POSIX_ROOT") .eqs. "" then define/process/translation=concealed SYS$POSIX_ROOT 'phys'
$! The CRTL maps /bin to SYS$SYSTEM unless BIN is a logical name; make
$! /bin/sh and friends resolve to GNV (GNV$STARTUP leaves this commented out).
$ if f$trnlnm("BIN") .eqs. "" then define/process BIN GNU:[BIN]
$ bash :== $GNU:[BIN]BASH.EXE
$ exit 1
