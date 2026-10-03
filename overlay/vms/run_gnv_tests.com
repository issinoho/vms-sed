$! RUN_GNV_TESTS.COM - run the upstream test suite under GNV bash
$!
$! Usage:  @[.VMS]RUN_GNV_TESTS [test-name ...]
$! Needs a built [.BIN_<arch>]SED.EXE and GNV (see GNV_ENV.COM).
$! Results: [.TESTSUITE]VMS-RESULTS.TXT and [.TESTSUITE.VMS-LOGS]
$!
$ set noon
$ saved_default = f$environment("DEFAULT")
$ proc = f$environment("PROCEDURE")
$ vmsdir = f$parse(proc,,,"DEVICE") + f$parse(proc,,,"DIRECTORY")
$ @'vmsdir'GNV_ENV.COM
$! Perl for the tests that need it (process-level names only).
$! Several versions may be installed; the last one found is the newest.
$ perl_setup = ""
$perl_loop:
$ f = f$search("SYS$COMMON:[PERL-5_*]PERL_SETUP.COM", 3)
$ if f .eqs. "" then goto perl_done
$ perl_setup = f
$ goto perl_loop
$perl_done:
$ if perl_setup .nes. "" then @'perl_setup'
$ set default 'vmsdir'
$ set default [-]
$ arch = f$edit(f$getsyi("ARCH_NAME"), "UPCASE")
$! The tests run "sed" from ./sed via PATH, and helpers from [.TESTSUITE].
$ copy/nolog [.BIN_'arch']SED.EXE [.SED]SED.EXE
$ purge/nolog [.SED]SED.EXE
$ mms/description=[.vms]descrip.mms/macro=("ARCH=''arch'") CHECK_PROGRAMS
$!
$! The tests ask for "en_US.UTF-8" and "fr_FR.UTF-8", which VMS does not ship
$! under those names.  Alias the newest generic UTF-8 locale to them in a
$! private directory searched first, for this process only.
$ locdir = f$environment("DEFAULT") - "]" + ".TESTSUITE.VMS-LOCALE]"
$ if f$search("[.TESTSUITE]VMS-LOCALE.DIR") .eqs. "" then create/directory 'locdir'
$ utf8 = ""
$ if f$search("SYS$I18N_LOCALE:UTF8-20.LOCALE") .nes. "" then utf8 = "UTF8-20"
$ if f$search("SYS$I18N_LOCALE:UTF8-30.LOCALE") .nes. "" then utf8 = "UTF8-30"
$ if f$search("SYS$I18N_LOCALE:UTF8-50.LOCALE") .nes. "" then utf8 = "UTF8-50"
$ if utf8 .eqs. "" then goto no_utf8
$ copy/nolog SYS$I18N_LOCALE:'utf8'.LOCALE 'locdir'EN_US_UTF-8.LOCALE
$ copy/nolog SYS$I18N_LOCALE:'utf8'.LOCALE 'locdir'FR_FR_UTF-8.LOCALE
$! Upstream asks for ja_JP.EUC-JP; VMS ships it as ja_JP.eucJP.
$ if f$search("SYS$I18N_LOCALE:JA_JP_EUCJP.LOCALE") .nes. "" then -
    copy/nolog SYS$I18N_LOCALE:JA_JP_EUCJP.LOCALE 'locdir'JA_JP_EUC-JP.LOCALE
$ purge/nolog 'locdir'
$! SYS$I18N_LOCALE is a search list; keep every element after ours.
$ i18n = ""
$ i = 0
$i18n_loop:
$ e = f$trnlnm("SYS$I18N_LOCALE",,i)
$ if e .eqs. "" then goto i18n_done
$ i18n = i18n + "," + e
$ i = i + 1
$ goto i18n_loop
$i18n_done:
$ define/process SYS$I18N_LOCALE 'locdir''i18n'
$ write sys$output "RUN_GNV_TESTS: en_US.UTF-8 and fr_FR.UTF-8 aliased to ''utf8'"
$no_utf8:
$ set process/parse_style=extended/case_lookup=blind
$! The perl tests (CuTmpdir.pm) refuse a working directory whose name has a
$! "$" in it, such as /USER$ROOT/...: run_gnv_tests.sh runs them from this
$! concealed rooted logical name, which GNV shows as /SEDTESTTOP/000000.
$! (Only them: GNV's diff cannot open absolute paths under it.)
$ top = f$environment("DEFAULT")
$ tdev = f$parse(top,,,"DEVICE","NO_CONCEAL")
$ tdir = f$parse(top,,,"DIRECTORY","NO_CONCEAL") - "][" - "]" + ".]"
$ define/process/translation_attributes=concealed SEDTESTTOP 'tdev''tdir'
$! sed's tests run from the top of the tree.
$ if p1 .nes. ""
$ then
$   bash vms/run_gnv_tests.sh 'p1' 'p2' 'p3' 'p4' 'p5' 'p6' 'p7' 'p8'
$   goto done
$ endif
$! Whole suite: a fresh bash per test (see run_gnv_tests.sh).
$ if f$search("[.testsuite]vms-results.txt") .nes. "" then delete/nolog [.testsuite]vms-results.txt;*
$ if f$search("[.testsuite.vms-logs]*.*") .nes. "" then delete/nolog [.testsuite.vms-logs]*.*;*
$ open/read tl [.VMS]TESTS.LST
$test_loop:
$ read/end=test_done tl t
$ bash vms/run_gnv_tests.sh --append "''t'"
$! A timeout that fires inside a test kills the whole GNV process tree in a
$! batch job, runner included, so no result line is written.  Record that.
$ search/nooutput [.testsuite]vms-results.txt " ''t' ("
$ if $severity .ne. 1
$ then
$   open/append rf [.testsuite]vms-results.txt
$   write rf "KILLED ''t' (no result: the test's own timeout fired and GNV killed the runner)"
$   close rf
$ endif
$ goto test_loop
$test_done:
$ close tl
$ bash vms/run_gnv_tests.sh --summary
$done:
$ set default 'saved_default'
$ exit 1
