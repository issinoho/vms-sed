#!/bin/sh
# run_gnv_tests.sh - run sed's upstream test suite under GNV bash on OpenVMS.
#
# Started by RUN_GNV_TESTS.COM with the top of the tree as the current
# directory (sed's suite runs from there: testsuite/<name>.sh, with sed in
# ./sed).  Mirrors the environment that testsuite/local.mk's
# TESTS_ENVIRONMENT provides, runs tests and writes:
#   testsuite/vms-results.txt   one line per test:
#                     PASS|FAIL|XFAIL|XPASS|SKIP|ERROR|TIMEOUT|EXCLUDED name (detail)
#   testsuite/vms-logs/<t>.log  output of each test that did not pass or skip
#                               (<t> is the test's file name, without testsuite/)
# Tests listed in vms/tests.skip (name, then reason) are not run.  Tests in
# vms/tests-upstream.xfail (upstream's XFAIL_TESTS) or vms/tests.xfail (GNV
# environment problems, not sed) run, but a failure is expected (XFAIL);
# a pass is XPASS.  Names in those lists are as in vms/tests.lst.
#
# Usage: run_gnv_tests.sh [test-name...]            fresh results (default: all tests)
#        run_gnv_tests.sh --append test-name...     add to existing results
#        run_gnv_tests.sh --summary                 append the summary line
# RUN_GNV_TESTS.COM runs the whole suite as one --append call per test: a
# long-lived GNV bash eventually exhausts the subprocess quota with children
# that tests leave behind, and a fresh bash per test avoids that.

top=$(pwd)
. "$top/vms/tests.env"

srcdir=.
top_srcdir=.
abs_srcdir=$top
abs_top_srcdir=$top
abs_top_builddir=$top
built_programs=sed
CONFIG_HEADER=$top/config.h
LC_ALL=C
AWK=awk
SHELL=/bin/sh
CC=false            # no host C compiler for tests that build helpers
# VSI Perl, made reachable by RUN_GNV_TESTS.COM (PERL_ROOT); else no perl.
if [ -f /perl_root/perl.exe ]; then PERL=/perl_root/perl; else PERL=false; fi
# fr_FR.UTF-8 and ja_JP.EUC-JP are aliased by RUN_GNV_TESTS.COM.
LOCALE_FR=fr_FR.ISO8859-1
LOCALE_FR_UTF8=fr_FR.UTF-8
LOCALE_JA=ja_JP.EUC-JP
MAKE=make
TMPDIR=$top/testsuite/vms-tmp
# As testsuite/local.mk: sed from ./sed; helpers (get-mb-cur-max) from testsuite.
PATH=$top/sed:$top/testsuite:$PATH
export VERSION PACKAGE_BUGREPORT srcdir top_srcdir abs_srcdir \
       abs_top_srcdir abs_top_builddir built_programs CONFIG_HEADER \
       LC_ALL AWK SHELL CC PERL LOCALE_FR LOCALE_FR_UTF8 LOCALE_JA MAKE TMPDIR PATH

res=testsuite/vms-results.txt
logs=testsuite/vms-logs

summary() {
    # Tests killed by a firing timeout are expected failures if listed as such.
    for t in $(sed -n 's/^KILLED \([^ ]*\) .*/\1/p' $res); do
        x=$(cat "$top/vms/tests-upstream.xfail" "$top/vms/tests.xfail" 2>/dev/null |
            sed -n "s|^$t[ 	][ 	]*||p" | head -1)
        [ -n "$x" ] && sed "s|^KILLED $t (\(.*\))\$|XFAIL $t (\1; $x)|" $res > $res.new &&
            mv $res.new $res
    done
    line="SUMMARY:"
    for s in PASS FAIL XFAIL XPASS SKIP ERROR TIMEOUT KILLED EXCLUDED; do
        line="$line $s=$(grep -c "^$s " $res)"
    done
    echo "$line" | tee -a $res
}

want_summary=
lower=1         # names typed at DCL arrive upper-cased
case ${1:-} in
--summary) summary; exit 0 ;;
--append) shift; lower= ;;   # RUN_GNV_TESTS.COM quotes names, keeping case
*) rm -rf testsuite/vms-tmp $logs; : > $res; want_summary=1 ;;
esac
mkdir -p testsuite/vms-tmp $logs

if [ $# -gt 0 ]; then
    if [ -n "$lower" ]; then tests=$(echo "$*" | tr A-Z a-z); else tests="$*"; fi
else
    tests=$(cat "$top/vms/tests.lst")
fi

for t in $tests; do
    case $t in testsuite/*) ;; *) t=testsuite/$t ;; esac
    base=${t#testsuite/}
    reason=$(sed -n "s|^$t[ 	][ 	]*||p" "$top/vms/tests.skip" 2>/dev/null)
    if [ -n "$reason" ]; then
        echo "EXCLUDED $t ($reason)" | tee -a $res
        continue
    fi
    # As testsuite/local.mk: .pl tests run under perl, the rest under sh.
    case $t in
    *.pl)
        if [ "$PERL" = false ]; then
            echo "SKIP $t (perl test, no perl available)" | tee -a $res
            continue
        fi
        set -- "$PERL" -w -Itestsuite -MCuSkip -MCoreutils "-MCuTmpdir qw($t)" ;;
    *)  set -- /bin/sh ;;
    esac
    start=$(date +%s)
    # No outer timeout: GNV's timeout, when a test's own timeout fires
    # inside it, takes the whole process tree down, runner included.
    # perl tests run from /SEDTESTTOP/000000 (see RUN_GNV_TESTS.COM): their
    # CuTmpdir.pm refuses a working directory with "$" in its name.
    case $t in
    *.pl) dir=/SEDTESTTOP/000000 ;;
    *)    dir=. ;;
    esac
    (cd "$dir" && SED_TEST_NAME=$(echo "$t" | tr / -) "$@" "./$t") > "$logs/$base.log" 2>&1
    rc=$?
    case $rc in
    0) status=PASS ;;
    77) status=SKIP ;;
    99) status=ERROR ;;
    124) status=TIMEOUT ;;
    *) status=FAIL ;;
    esac
    detail="$(( $(date +%s) - start ))s, rc=$rc"
    xfail=$(cat "$top/vms/tests-upstream.xfail" "$top/vms/tests.xfail" 2>/dev/null |
            sed -n "s|^$t[ 	][ 	]*||p" | head -1)
    if [ -n "$xfail" ]; then
        case $status in FAIL) status=XFAIL; detail="$detail; $xfail" ;; PASS) status=XPASS ;; esac
    fi
    why=
    if [ $status = SKIP ]; then
        why=$(sed -n 's/.*skipped test: //p' "$logs/$base.log" | head -1)
        detail="$detail; ${why:-no reason given}"
    fi
    # Keep the log of a skip that gave no reason, so it can be found.
    case $status in
    PASS) rm -f "$logs/$base.log" ;;
    SKIP) [ -n "$why" ] && rm -f "$logs/$base.log" ;;
    esac
    echo "$status $t ($detail)" | tee -a $res
done

[ -n "$want_summary" ] && summary
exit 0
