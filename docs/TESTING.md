# Testing GNU sed on OpenVMS

There are two layers:

| Layer | Runs on | Needs | Command (host) |
|---|---|---|---|
| DCL smoke test, 25 checks | IA64, x86-64 | nothing extra | `tools/test.sh <node>` |
| Upstream test suite, 75 tests | x86-64 | GNV (bash 4.4 + coreutils), VSI Perl | `tools/gnvtest.sh x86` |

Failures that look environmental are re-run **natively** before they are classified: a
VSI Perl script writes the exact input bytes, runs our `SED.EXE` through a DCL `PIPE`, and
compares the output byte for byte. Every reason below that says "natively" was checked
that way, on IA64.

## DCL smoke test (`vms/test_smoke.com`)
The main commands and options, exit statuses as seen by DCL, `-i` and `-i.bak`, the `w`
command, a line containing byte 0xFF, and output to a DCL `PIPE` (each line must arrive as
one record). It also runs against an installed kit.

## Upstream suite under GNV (`vms/run_gnv_tests.sh`, `vms/run_gnv_tests.com`)
This mirrors `testsuite/local.mk`'s `TESTS_ENVIRONMENT`: tests run from the top of the tree
as `testsuite/<name>`, with sed in `./sed` and the helpers `get-mb-cur-max` and
`test-mbrtowc` (built by the MMS target `CHECK_PROGRAMS`) in `testsuite/`. `.pl` tests run
under VSI Perl, the rest under `/bin/sh`, with a fresh bash per test. The procedure also
aliases `en_US.UTF-8`, `fr_FR.UTF-8` and `ja_JP.EUC-JP` to VMS locales, and defines the
rooted logical `SEDTESTTOP`: the Perl tests run from it because `CuTmpdir.pm` refuses a
working directory with a `$` in its name (`/USER$ROOT/...`).

The test framework needed four patches to run at all on VMS (0008-0011, see README).

### Excluded (`vms/tests.skip`)
| Test | Reason |
|---|---|
| obinary.sh | Hangs under GNV: its first step, printf a \| sed cb (a pipe whose data has no final newline), never sees end of file; natively through a DCL PIPE sed handles that input. The test is about Windows O_TEXT, which does not apply |
| panic-tests.sh | Needs mkfifo (its later checks read from a FIFO); VMS has no FIFOs. The checks before that point pass |
| read-error-stale-errno.sh | Needs mkfifo; VMS has no FIFOs |
| stdin.sh | Hangs under GNV: two seds in a subshell share one stdin, read through a pipe ((sed d; sed G) < file, cat \| (...)); VMS processes do not share file offsets, as for unbuffered.sh |

### Expected failures (`vms/tests.xfail`)
None of these is a sed fault; each reason was verified.

| Test | Reason |
|---|---|
| misc.pl | 10 cases whose input or expected output has no final newline or uses NULs: the GNV-created files gain a newline per write; all 10 pass natively via VSI Perl with exact bytes |
| nulldata.sh | The -z cases' input and expected files are written by GNV printf, which ends every write with a newline; the three -z cases pass natively with exact bytes |
| compile-errors.sh | One case (s-opt-r): the script "s/./x/\r" is written by GNV printf, whose record loses the bare CR, so sed sees a valid command; natively sed rejects it with "unknown option to 's'" as expected |
| execute-tests.sh | Sed's e command and s///e run their command through the C library's system()/popen(), which on OpenVMS is DCL, not /bin/sh |
| in-place-suffix-backup.sh | Compares the exact strerror text: the VMS C runtime says "no such file or directory" where glibc says "No such file or directory" |
| posix-mode-s.sh | One check (s///e without --posix) runs its command through system(), which on OpenVMS is DCL, not /bin/sh |
| sandbox.sh | One check runs the e command without --sandbox, through system(), which on OpenVMS is DCL, not /bin/sh |
| 8to7.sh | Its input is built from several printf writes per line, and GNV printf ends every write with a newline, so the lines are split; natively the l output is byte-exact (669 bytes) |
| eval.sh | The e command and s///e run their commands through system(), which on OpenVMS is DCL, not /bin/sh |
| unbuffered.sh | Sed -u 1q must leave the rest of a shared stdin for the next command (wc); VMS processes do not share file offsets (as grep's yesno test) |
| bsd-wrapper.sh | Only bsd.sh's section markers differ: MARK=`expr $MARK + 1` inside a function that has done exec >>$LOG comes back empty under GNV bash; every line sed produced matches bsd.good |

## Current results (sed 4.10)
| Suite | IA64 | x86-64 |
|---|---|---|
| DCL smoke test | 25/25 | 25/25 |
| Upstream suite | (no usable GNV) | 50 pass, 0 unexpected failures, 11 expected failures, 10 skipped, 4 excluded |

The skips: five tests need valgrind; one is "very expensive" (skipped upstream unless
`RUN_VERY_EXPENSIVE_TESTS=yes`); the rest need SELinux or locales VMS does not ship
(`el_GR.iso88597`, `ru_RU.UTF-8`) or ships broken (`ja_JP.sjis`).

`unbuffered.sh` and `bsd-wrapper.sh` were added to the expected failures during the final
run, which therefore reported them as FAIL; the figures above count them as expected.

## VMS bugs found by the suite
- **The CRTL's UTF-8 `mbrtowc` keeps no state** (patch 0012). A character given one byte per
  call never completes, and a lone byte that cannot start a character (0x80-0xC1,
  0xF5-0xFF) is reported as incomplete rather than invalid. sed reads delimiters a byte at a
  time, so a valid script was rejected (`mb-bad-delim`, `mb-match-slash`).
- **An open file cannot be deleted** (patch 0013). When `sed -i` failed, the atexit cleanup
  unlinked the temporary while it was still open, and `sedXXXXXX` was left behind
  (`temp-file-cleanup`).

## GNV and VSI Perl limits found along the way
- GNV `printf` to a file ends every write with a newline; a bare `\r` at the end of a record
  is lost.
- GNV's `diff` cannot open `/dev/null`, nor absolute paths under a rooted logical.
- A GNV pipe whose data lacks a final newline, or a stdin shared by two commands in a
  subshell, can hang the test (`obinary.sh`, `stdin.sh`).
- VSI Perl: `system` with a string runs DCL; a bash started from Perl does not inherit the
  environment; `File::Temp::tempdir` wants a VMS directory template; `$? = 0` in an END
  block makes perl exit with status 1.
