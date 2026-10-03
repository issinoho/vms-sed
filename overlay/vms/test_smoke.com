$! TEST_SMOKE.COM - quick functional check of a built or installed SED.EXE
$!
$! Usage:  @[.VMS]TEST_SMOKE [sed-image]
$!         The default image is [.BIN_<arch>]SED.EXE in this tree.
$! Exits with SS$_NORMAL if every test passes, otherwise reports failures.
$!
$ set noon
$ on control_y then goto finish
$ saved_default = f$environment("DEFAULT")
$ saved_parse = f$getjpi("", "PARSE_STYLE_PERM")
$ set process/parse_style=extended
$ proc = f$environment("PROCEDURE")
$ vmsdir = f$parse(proc,,,"DEVICE") + f$parse(proc,,,"DIRECTORY")
$ set default 'vmsdir'
$ set default [-]
$ arch = f$edit(f$getsyi("ARCH_NAME"), "UPCASE")
$ image = p1
$ if image .eqs. "" then image = f$parse("[.BIN_''arch']SED.EXE")
$ if f$search(image) .eqs. ""
$ then
$   write sys$error "SMOKE: no image ''image'"
$   exit 44
$ endif
$ sed := $'image'
$ pass == 0
$ fail == 0
$ if f$search("SMOKE_TMP.DIR") .eqs. "" then create/directory [.SMOKE_TMP]
$ set default [.SMOKE_TMP]
$ if f$search("*.*;*") .nes. "" then delete/nolog *.*;*
$!
$! --- fixtures -------------------------------------------------------------
$ create fruit.txt
apple
Banana
cherry pie
apple tart
grape
$ create script.sed
s/cherry/CHERRY/
/grape/d
$!
$! --- tests: name, expected exit code, expected output (| = newline), args --
$ call t version   0 ""                                          "--version"
$ call t subst     0 "APPLE|Banana|cherry pie|APPLE tart|grape"   """s/apple/APPLE/"" fruit.txt"
$ call t global    0 "Apple|BAnAnA|Apple tArt|grApe"                                 "-n ""s/a/A/gp"" fruit.txt"
$ call t nth       0 "BananA"                                    "-n ""/an/{s/a/A/3;p}"" fruit.txt"
$ call t print     0 "apple|apple tart"                          "-n ""/apple/p"" fruit.txt"
$ call t delete    0 "Banana|cherry pie|grape"                   """/apple/d"" fruit.txt"
$ call t lineno    0 "Banana"                                    "-n ""2p"" fruit.txt"
$ call t range     0 "Banana|cherry pie"                         "-n ""2,3p"" fruit.txt"
$ call t lastline  0 "grape"                                     "-n ""$p"" fruit.txt"
$ call t icase     0 "X"                                         "-n ""s/banana/X/Ip"" fruit.txt"
$ call t extended  0 "ppale|ppale tart|grpae"                       "-n -E ""s/(a)(p+)/\2\1/p"" fruit.txt"
$ call t backref   0 "pp"                                        "-n ""s/.*\(p\)\1.*/\1\1/p;q"" fruit.txt"
$ call t translit  0 "APPLE"                                     "-n ""1y/aple/APLE/p"" fruit.txt"
$ call t multi     0 "APPLE|BANANA"                              "-n -e ""1,2y/abelnp/ABELNP/"" -e ""1,2p"" fruit.txt"
$ call t scriptf   0 "apple|Banana|CHERRY pie|apple tart"        "-f script.sed fruit.txt"
$ call t reverse   0 "grape|apple tart|cherry pie|Banana|apple"  "-n ""1!G;h;$p"" fruit.txt"
$ call t append    0 "apple|-|Banana"                            "-n ""1{p;a\" -e ""-"" -e ""};2p"" fruit.txt"
$ call t count     0 "5"                                         "-n ""$="" fruit.txt"
$ call t quitcode  7 "apple|Banana"                              """2q7"" fruit.txt"
$ call t nofile    2 ""                                          """p"" no_such_file.txt"
$ call t badcmd    1 ""                                          """k"" fruit.txt"
$!
$! In-place editing: the file is rewritten, and -i.bak keeps the original.
$ copy/nolog fruit.txt edit.txt
$ define/user sys$output nla0:
$ sed "-i.bak" "s/grape/GRAPE/" edit.txt
$ st = ($status .and. %X7F8) / 8
$ call readfile edit.txt
$ new = rfgot
$ call readfile edit.txt.bak
$ if st .eq. 0 .and. new .eqs. "apple|Banana|cherry pie|apple tart|GRAPE" .and. -
     rfgot .eqs. "apple|Banana|cherry pie|apple tart|grape"
$ then
$   write sys$output "PASS INPLACE-BACKUP"
$   pass == pass + 1
$ else
$   write sys$output "FAIL INPLACE-BACKUP: exit ", st, " file [", new, "] backup [", rfgot, "]"
$   fail == fail + 1
$ endif
$ define/user sys$output nla0:
$ sed "-i" "1d" edit.txt
$ st = ($status .and. %X7F8) / 8
$ call readfile edit.txt
$ if st .eq. 0 .and. rfgot .eqs. "Banana|cherry pie|apple tart|GRAPE"
$ then
$   write sys$output "PASS INPLACE"
$   pass == pass + 1
$ else
$   write sys$output "FAIL INPLACE: exit ", st, " file [", rfgot, "]"
$   fail == fail + 1
$ endif
$!
$! The w command writes matching lines to a file.
$ define/user sys$output nla0:
$ sed "-n" "/apple/w wout.txt" fruit.txt
$ call readfile wout.txt
$ if rfgot .eqs. "apple|apple tart"
$ then
$   write sys$output "PASS WFILE"
$   pass == pass + 1
$ else
$   write sys$output "FAIL WFILE: [", rfgot, "]"
$   fail == fail + 1
$ endif
$!
$! A line containing byte 0xFF must be written intact (signed char vs EOF).
$ open/write hb highbyte.txt
$ hi = "a"
$ hi[8,8] = 255
$ hi = hi + "b"
$ write hb hi
$ close hb
$ define/user sys$output out.txt
$ define/user sys$error out.txt
$ sed "p;d" highbyte.txt
$ st = $status
$ got = ""
$ open/read hb out.txt
$ read/end=hb_eof hb got
$hb_eof:
$ close hb
$ if ((st .and. %X7F8) / 8) .eq. 0 .and. got .eqs. hi
$ then
$   write sys$output "PASS HIGHBYTE"
$   pass == pass + 1
$ else
$   write sys$output "FAIL HIGHBYTE: line with byte 255 not written intact"
$   fail == fail + 1
$ endif
$!
$! Output to a record-oriented destination (a PIPE mailbox): each output line
$! must arrive as one record, not one record per write or per character.
$ pipe sed "-n" "/tart/=;/tart/p" fruit.txt | search/nooutput sys$pipe "apple tart"/match=and/exact
$ if $severity .eq. 1
$ then
$   write sys$output "PASS PIPE-RECORDS"
$   pass == pass + 1
$ else
$   write sys$output "FAIL PIPE-RECORDS: ""apple tart"" not found as one record in piped output"
$   fail == fail + 1
$ endif
$!
$finish:
$ set default 'vmsdir'
$ set default [-]
$ set process/parse_style='saved_parse'
$ write sys$output "SMOKE: ''pass' passed, ''fail' failed (''image')"
$ set default 'saved_default'
$ if fail .eq. 0 .and. pass .gt. 0 then exit 1
$ exit 44
$!
$! --- T name expected-exit expected-output args -------------------------
$t: subroutine
$ set noon
$ if f$search("out.txt") .nes. "" then delete/nolog out.txt;*
$ define/user sys$output out.txt
$ define/user sys$error out.txt
$ sed 'p4'
$ st = $status
$! _POSIX_EXIT: the C exit code is in bits 3..10 of the VMS status.
$ code = (st .and. %X7F8) / 8
$ got = ""
$ if f$search("out.txt") .eqs. "" then goto compare
$ open/read f out.txt
$readloop:
$ read/end=readdone f line
$ if got .nes. "" then got = got + "|"
$ got = got + line
$ if f$length(got) .gt. 200 then goto readdone
$ goto readloop
$readdone:
$ close f
$compare:
$ ok = code .eq. f$integer(p2)
$! (DCL upper-cases the unquoted test name.)
$ if p1 .nes. "VERSION" .and. p2 .ne. 2 then ok = ok .and. (got .eqs. p3)
$ if p1 .eqs. "VERSION" then ok = ok .and. (f$locate("sed (GNU sed)", got) .lt. f$length(got))
$ if ok
$ then
$   write sys$output "PASS ", p1
$   pass == pass + 1
$ else
$   write sys$output "FAIL ", p1, ": exit ", code, " (want ", p2, "), output [", got, "] (want [", p3, "])"
$   fail == fail + 1
$ endif
$ exit 1
$ endsubroutine
$!
$! --- READFILE file: lines of file joined with | into global symbol rfgot ---
$readfile: subroutine
$ set noon
$ rfgot == ""
$ if f$search(p1) .eqs. "" then exit 1
$ open/read rf 'p1'
$rf_loop:
$ read/end=rf_done rf line
$ if rfgot .nes. "" then rfgot == rfgot + "|"
$ rfgot == rfgot + line
$ if f$length(rfgot) .gt. 200 then goto rf_done
$ goto rf_loop
$rf_done:
$ close rf
$ exit 1
$ endsubroutine
