$! VMS_INSTALLCHECK.COM <tree-dir-name> - install the kit, verify, smoke-test the
$! installed image, then remove it.  Changes the system while it runs (PCSI
$! database, SYS$COMMON:[SED], system logical SED$ROOT); leaves it as it was.
$ set noon
$ arch = f$edit(f$getsyi("ARCH_NAME"), "UPCASE")
$ base = "I64VMS"
$ if arch .eqs. "X86_64" then base = "X86VMS"
$ tree = f$environment("DEFAULT") - "]" + "." + p1 + "]"
$ kitdir = tree - "]" + ".KIT_''arch']"
$ write sys$output "=== INSTALL from ", kitdir
$ product install SED /producer=ISSINOHO /base_system='base' /source='kitdir' /options=noconfirm /log
$ write sys$output "=== install status ", $status
$ product show product SED /producer=ISSINOHO
$ write sys$output "=== VERIFY"
$ write sys$output "startup procedure: [", f$search("SYS$STARTUP:SED$STARTUP.COM"), "]"
$ show logical SED$ROOT
$ directory/nohead/notrail SED$ROOT:[000000...]*.*
$ @SED$ROOT:[000000]SED$SETUP.COM
$ show symbol sed
$ sed --version
$ create inst_test.txt
alpha
Beta
$ write sys$output "sed (traditional parse style):"
$ set process/parse_style=traditional
$ sed "s/Beta/Gamma/" inst_test.txt
$ delete/nolog inst_test.txt;*
$ write sys$output "=== SMOKE TEST on installed image"
$ smoke = tree - "]" + ".VMS]TEST_SMOKE.COM"
$ @'smoke' SED$ROOT:[BIN]SED.EXE
$ write sys$output "=== REMOVE"
$ product remove SED /producer=ISSINOHO /options=noconfirm /log
$ write sys$output "=== remove status ", $status
$ write sys$output "SED$ROOT after removal: [", f$trnlnm("SED$ROOT"), "]"
$ write sys$output "files after removal: [", f$search("SYS$COMMON:[SED...]*.*"), "]"
$ write sys$output "startup after removal: [", f$search("SYS$STARTUP:SED$STARTUP.COM"), "]"
$ product show product SED /producer=ISSINOHO
$ delete/symbol/global sed
