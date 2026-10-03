# CLAUDE.md

Guidance for working in this repository: a port of GNU sed to OpenVMS (IA64 and x86-64)
that stores only our deltas over the upstream release tarball. It is built with exactly the
methods of its sibling `~/projects/vms-grep` (github.com/issinoho/vms-grep), and the tools
are copies of grep's. Read README.md first; it describes the workflow and design. This
file covers the rules and the pitfalls.

## Ground rules

- **Never edit `staging/`, `cache/` or `out/`.** They are regenerated. Every VMS change is
  either a patch (`patches/NNNN-*.patch`, listed in `patches/series`) or a new file in
  `overlay/`. `tools/prepare.sh` refuses overlay files that would replace upstream files.
- **Change an upstream file with a patch.** Make a pristine copy under `a/` and an edited
  copy under `b/`, run `diff -u a/<path> b/<path>`, and put a `Subject:` line and a short
  explanation above the diff. Guard VMS-only code with `#ifdef __VMS` so the patch could go
  upstream. Patches to the same file stack, so diff against the tree as it stands after the
  earlier patches.
- **Configuration answers** go in `overlay/vms/config/vms-manual.site`, each with a comment
  explaining why. Plain `var=value` lines there override the generated
  `configure-<node>.cache`. Overriding a gnulib result often needs its `gl_cv_*` variable
  too, not just `ac_cv_*` (`mempcpy` needed `gl_cv_onwards_func_mempcpy`).
- **Test exceptions** go in `overlay/vms/tests.skip` (not run) or `overlay/vms/tests.xfail`
  (expected to fail), always with a reason. Before calling a failure "environmental",
  verify sed's behaviour natively; `docs/TESTING.md` records how. Upstream's own
  `XFAIL_TESTS` are picked up automatically.
- **Committed files must not contain real node details.** Use `<ia64-host>`, `<x86-host>`
  and `DISK$USER:[USERNAME.VMS_GREP]`. The real values live only in the git-ignored
  `tools/nodes.conf`.
- Keep `docs/TESTING.md` and the README status table in step with test results.

## sed specifics

- **One non-recursive Makefile.** sed's automake variables (`lib_libsed_a_SOURCES`,
  `sed_sed_SOURCES`, `TESTS`, ...) are all read from the top-level Makefile in
  `tools/prepare.sh`; there are no `lib/`, `src/`, `tests/` Makefiles as in grep.
- **The tests run from the top of the tree** (`testsuite/<name>.sh`, with sed in `./sed`),
  and `vms/tests.lst`, `tests.skip` and `tests.xfail` name them as `testsuite/<name>`.
- **Generated `lib/malloc/*.gl.h`** are renamed `*_gl.h` by `prepare.sh` (VSI C cannot
  include a name with two dots); patch 0005 includes them by that name.
- **`sed -i`** writes a new version of the file (the old one stays as the previous version);
  `-i.bak` renames the original to `name^.ext.bak` and writes the edit in its place. The
  rewritten file is Stream_LF whatever the original's record format.

## Commands

```sh
tools/prepare.sh                        # always first after changing patches/overlay
tools/build.sh <ia64|x86> [ALL|CLEAN] [KEEP_GOING]
tools/test.sh <node>                    # smoke test
tools/gnvtest.sh x86 [tests...]         # upstream suite (x86 only; ~90 min for all)
tools/vms.sh <node> dcl '<cmd>' ...     # run DCL; also run/batch/put/get
tools/kit.sh <node>                     # PCSI kit -> out/kits/ (producer ISSINOHO)
tools/installcheck.sh <node>            # install kit, verify, smoke-test, remove (changes system; ask first)
tools/vms_configure.sh <node>           # once per upstream release, 45-65 min
```

Run long operations (full builds take ~30 min on IA64 and longer on the x86 VM; the test
suite ~90 min; configure up to 70 min) with `run_in_background` and poll for completion.
MMS does not track compiler flags: after changing `ccflags.txt` or `CFLAGS` in
`descrip.mms`, run `tools/build.sh <node> CLEAN` first.

## VMS and tooling pitfalls (learned the hard way)

- **Use `tools/vms.sh`, never raw `ssh host cmd`.** Raw ssh output is often lost, and
  sessions sometimes never close. vms.sh logs to a file and waits for a completion marker.
- **Never use `WAIT` in DCL run over ssh**; it hangs (batch jobs are fine).
- **Never edit a bash script that is running.** bash reads scripts incrementally. Replace
  long-running tools atomically (write a copy, then `mv`).
- **Don't use `pkill -f` / `pgrep -f`** with a pattern that also matches your own shell's
  command line. Kill by explicit PID. On VMS, stop only processes this session started
  (they are network/batch processes of the work account); leave interactive sessions alone.
- **DCL details:**
  - `F$SEARCH` with a wildcard needs a stream id when other `F$SEARCH` calls happen in the
    same loop.
  - Batch jobs default to `/LIST` and `/MAP`.
  - DCL command lines are limited to about 4096 bytes (hence the wildcard librarian step).
  - `CALL` arguments are upper-cased unless quoted.
  - `SYS$LOGIN:[.X]` is not valid on these nodes.
- **`sftp put -r` into an existing directory nests a copy**; push.sh uploads file by file.
- **Run `tools/prepare.sh` after every change to `patches/` or `overlay/`.** build.sh and
  kit.sh push whatever is in `staging/`; forgetting this once shipped a stale kit.
- **stdout on VMS is often record-oriented** (terminal, `/OUTPUT` log, mailbox). The CRTL
  turns each `fwrite` item into a record (patch 0004 writes with `putc`), and a host-side
  `grep` treats output containing a NUL as binary (use `grep -a`).
- **GNV quirks:**
  - Shell functions inside pipelines get the wrong arguments.
  - Empty arguments are dropped when bash runs a VMS image.
  - VMS pipes have no SIGPIPE.
  - A `timeout` that fires in a batch job kills the whole process tree.
  - IA64's GNV is bash 1.14 and cannot run the upstream suite; use the regex tables there.
  - `printf` to a VMS file ends every write with a newline (each write is a record), so
    tests that build exact bytes with printf fail; verify them natively with VSI Perl.
  - An assignment prefix on a function call (`LC_ALL=x func`) stays set afterwards.
- **Running sed from VSI Perl:** Perl's own `>file` redirection in `system()` does not
  work; use `system("pipe sed ... > file")`. A bash started from Perl through DCL does not
  inherit the environment (patch 0010 exports PATH and the locale variables).
- **VSI Perl quirks** (the `.pl` tests): `File::Temp::tempdir` wants a VMS directory
  template; `$? = 0` in an END block makes perl exit 1 (patch 0009); `CuTmpdir.pm` refuses
  a working directory with `$` in its name, so `RUN_GNV_TESTS.COM` runs the suite from
  the rooted logical `SEDTESTTOP`.
- **CRTL quirks** that matter (shared with grep) are documented in
  vms-grep's `docs/vms-environment.md`:
  - no `#include_next`; text-library includes instead;
  - `open()` of a directory fails;
  - `setlocale("")` ignores environment variables;
  - UTF-8 decoding bugs;
  - `mempcpy` is a macro;
  - argument case under traditional parse style.

## Commits

Commit in logical steps with messages that explain the VMS reason for each change. Don't
push without the user asking. The GitHub remote is `origin`
(github.com/issinoho/vms-sed), branch `main`.
