$! SED$SETUP.COM - define the sed command for a user
$!
$! Add to LOGIN.COM (or SYS$MANAGER:SYLOGIN.COM for everyone):
$!     $ @SED$ROOT:[000000]SED$SETUP.COM
$!
$! Quote sed scripts and upper-case options, or SET PROCESS/PARSE_STYLE=EXTENDED:
$! traditional DCL parsing changes the case of unquoted arguments.
$!
$ if f$trnlnm("SED$ROOT") .eqs. ""
$ then
$   write sys$error "SED$SETUP: SED$ROOT is not defined; run SED$STARTUP.COM first"
$   exit 44
$ endif
$ sed :== $SED$ROOT:[BIN]SED.EXE
$ exit 1
