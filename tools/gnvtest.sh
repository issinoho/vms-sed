#!/usr/bin/env bash
# gnvtest.sh <node> [test...] - run the upstream test suite under GNV bash on <node>.
#
# Pushes the prepared tree (and rebuilds if needed), runs [.VMS]RUN_GNV_TESTS.COM
# as a batch job, then fetches results to out/gnvtests-<node>/:
#   results.txt  one line per test, and logs/<test>.log for each non-passing test.
set -euo pipefail

top=$(cd "$(dirname "$0")/.." && pwd)
node=${1:?usage: gnvtest.sh <node> [test...]}; shift
. "$top/upstream.conf"
remote=$(echo "$UPSTREAM_NAME-$UPSTREAM_VERSION" | tr . _)
REMOTE=$(echo "$remote" | tr a-z A-Z)
read -r _ _ _ _ _ WORKDIR SFTPDIR < <(awk -v n="$node" '$1==n' "$top/tools/nodes.conf")

"$top/tools/build.sh" "$node" > "$top/out/build-$node.log" 2>&1 ||
    { tail -20 "$top/out/build-$node.log"; echo "gnvtest: build failed" >&2; exit 1; }

job=$top/cache/gnvtests-$node.com
printf '$ set noon\n$ @%s.%s.VMS]RUN_GNV_TESTS.COM %s\n' "${WORKDIR%]}" "$REMOTE" "$*" > "$job"
VMS_BATCH_POLL_SECS=60 VMS_BATCH_POLLS=600 "$top/tools/vms.sh" "$node" batch "$job" > /dev/null

dest=$top/out/gnvtests-$node
rm -rf "$dest"; mkdir -p "$dest/logs"
"$top/tools/vms.sh" "$node" get "$remote/tests/vms-results.txt" "$dest/results.raw"
tr -d '\r' < "$dest/results.raw" > "$dest/results.txt"; rm -f "$dest/results.raw"
for t in $(awk '$1!="KILLED" && $1!="PASS" && !($1=="SKIP" && !/no reason given/) && $1!="EXCLUDED" && $1!="SUMMARY:" {print $2}' "$dest/results.txt"); do
    "$top/tools/vms.sh" "$node" get "$remote/tests/vms-logs/$t.log" "$dest/logs/$t.log" 2>/dev/null || true
done
tail -1 "$dest/results.txt"
