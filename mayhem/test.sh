#!/usr/bin/env bash
#
# mayhem/test.sh — RUN crown's own unit-test suite (src/core/unit_tests.cpp, built by mayhem/build.sh)
# plus a known-answer probe. exit 0 = pass. The unit tests ENSURE() values and abort on a failure; the
# probe's exact output is diffed below, so a neutered (exit(0)) program fails both checks.
#
# IMPORTANT:
#  * Must assert BEHAVIOR/OUTPUT, not just exit status. The oracle has to check asserted values /
#    golden-output diffs / known-answer results — so a PATCH that "fixes" a bug by making the program
#    exit(0) (or any no-op) FAILS here. Running inputs and checking only "exit 0 / didn't crash" is
#    NOT a functional test (it's trivially reward-hackable) — use the project's real assertion suite.
#  * Do NOT build here — mayhem/build.sh already compiled the test suite (with the project's normal
#    flags). This script only RUNS the pre-built tests and reports counts. If the test runner is
#    missing, that's a build.sh bug — fail loudly rather than silently rebuilding.
#  * REQUIRED OUTPUT — a CTRF (https://ctrf.io) summary so Mayhem/the PATCH grader reads the counts:
#      - writes a CTRF JSON report to ${CTRF_REPORT:-$SRC/ctrf-report.json}, and
#      - prints a one-line `CTRF {...}` marker to stdout (same JSON, compact).
#    Only `results.summary` (with tests/passed/failed/pending/skipped/other) is required.
#    Use the emit_ctrf helper below; it computes tests = passed+failed+skipped and sets the exit
#    code (0 iff failed==0). Map your framework's output to passed/failed/skipped.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"   # build parallelism; env-overridable, falls back to nproc (use -j"$MAYHEM_JOBS")
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

BIN="$SRC/build/mayhem"
for b in unit_tests kat_probe; do
  [ -x "$BIN/$b" ] || { echo "missing $BIN/$b — mayhem/build.sh should have built it" >&2; emit_ctrf crown-unit 0 1 0; exit 1; }
done

# 1) The engine's unit tests: each prints its name, then runs; a failed ENSURE() aborts the process.
expected=$(grep -c '^[[:space:]]*{ "test_' src/core/unit_tests.cpp)
out=$("$BIN/unit_tests" 2>&1); rc=$?
ran=$(printf '%s\n' "$out" | grep -c '^test_')
if [ "$rc" -eq 0 ] && [ "$ran" -eq "$expected" ] && [ "$expected" -gt 30 ]; then
  passed=$ran; failed=0
else
  echo "unit tests FAILED: rc=$rc ran=$ran expected=$expected" >&2
  printf '%s\n' "$out" | tail -5 >&2
  passed=$(( ran > 0 ? ran - 1 : 0 )); failed=1
fi

# 2) Known answers through the parsers (golden output; bash does the comparison).
golden='keys=4
name=crown
count=42
flag=1
size=1.00,2.50,-3.00
guid=1 961..884
expr=8.50'
if [ "$("$BIN/kat_probe" 2>&1)" = "$golden" ]; then
  passed=$(( passed + 1 ))
else
  echo "kat_probe output differs from golden:" >&2
  "$BIN/kat_probe" >&2 || true
  failed=$(( failed + 1 ))
fi

emit_ctrf "crown-unit-tests" "$passed" "$failed" 0
