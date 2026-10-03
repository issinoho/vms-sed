$! VMS_INSTALLCHECK.COM <tree-dir-name> - install the kit, verify, smoke-test the
$! installed image, then remove it.  Changes the system while it runs (PCSI
$! database, SYS$COMMON:[GREP], system logical GREP$ROOT); leaves it as it was.
$ set noon
$ arch = f$edit(f$getsyi("ARCH_NAME"), "UPCASE")
$ base = "I64VMS"
$ if arch .eqs. "X86_64" then base = "X86VMS"
$ tree = f$environment("DEFAULT") - "]" + "." + p1 + "]"
$ kitdir = tree - "]" + ".KIT_''arch']"
$ write sys$output "=== INSTALL from ", kitdir
$ product install GREP /producer=ISSINOHO /base_system='base' /source='kitdir' /options=noconfirm /log
$ write sys$output "=== install status ", $status
$ product show product GREP /producer=ISSINOHO
$ write sys$output "=== VERIFY"
$ write sys$output "startup procedure: [", f$search("SYS$STARTUP:GREP$STARTUP.COM"), "]"
$ show logical GREP$ROOT
$ directory/nohead/notrail GREP$ROOT:[000000...]*.*
$ @GREP$ROOT:[000000]GREP$SETUP.COM
$ show symbol grep
$ show symbol egrep
$ grep --version
$ create inst_test.txt
alpha
Beta
gamma|delta
$ write sys$output "egrep (traditional parse style):"
$ set process/parse_style=traditional
$ egrep "^(alpha|Beta)" inst_test.txt
$ write sys$output "fgrep:"
$ fgrep "a|d" inst_test.txt
$ delete/nolog inst_test.txt;*
$ write sys$output "=== SMOKE TEST on installed image"
$ smoke = tree - "]" + ".VMS]TEST_SMOKE.COM"
$ @'smoke' GREP$ROOT:[BIN]GREP.EXE
$ write sys$output "=== REMOVE"
$ product remove GREP /producer=ISSINOHO /options=noconfirm /log
$ write sys$output "=== remove status ", $status
$ write sys$output "GREP$ROOT after removal: [", f$trnlnm("GREP$ROOT"), "]"
$ write sys$output "files after removal: [", f$search("SYS$COMMON:[GREP...]*.*"), "]"
$ write sys$output "startup after removal: [", f$search("SYS$STARTUP:GREP$STARTUP.COM"), "]"
$ product show product GREP /producer=ISSINOHO
$ delete/symbol/global grep
$ delete/symbol/global egrep
$ delete/symbol/global fgrep
