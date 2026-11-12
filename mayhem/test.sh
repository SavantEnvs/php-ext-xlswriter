#!/usr/bin/env bash
#
# mayhem/test.sh — RUN this repo's OWN functional test suite (already built by mayhem/build.sh).
# exit 0 = pass. EDIT per repo. PATCH-grade oracle: after an agent patches the source, the grader
# rebuilds (build.sh) then runs this. DELETE this file if the repo has no meaningful tests.
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

# libxlsx's own suites (built by build.sh): the writer suite (ctest) and the reader / integration /
# edit / formula suites (unity). Each is a dynamically linked binary that asserts values; their
# summary lines are parsed (a neutered binary prints none, so the missing summary fails loudly).
T="$SRC/library/libxlsx/test"
cd "$T"

passed=0; failed=0; skipped=0; missing=0

# writer (ctest): "RESULTS: N tests (P ok, F failed, S skipped) ran/total in X ms"
if [ ! -x writer/test_all ]; then echo "missing writer/test_all (build.sh bug)" >&2; missing=1; fi
out=$(writer/test_all 2>&1 || true)
if line=$(printf '%s\n' "$out" | grep -E '^RESULTS: [0-9]+ tests \([0-9]+ ok, [0-9]+ failed, [0-9]+ skipped\)' | tail -1); then
  p=$(printf '%s' "$line" | sed -E 's/^RESULTS: [0-9]+ tests \(([0-9]+) ok, ([0-9]+) failed, ([0-9]+) skipped\).*/\1/')
  f=$(printf '%s' "$line" | sed -E 's/^RESULTS: [0-9]+ tests \(([0-9]+) ok, ([0-9]+) failed, ([0-9]+) skipped\).*/\2/')
  s=$(printf '%s' "$line" | sed -E 's/^RESULTS: [0-9]+ tests \(([0-9]+) ok, ([0-9]+) failed, ([0-9]+) skipped\).*/\3/')
  passed=$((passed+p)); failed=$((failed+f)); skipped=$((skipped+s))
else
  echo "no ctest summary from writer/test_all" >&2; missing=1
fi

# unity-style: "N tests, F failures"
for src in reader/test_*.c integration/test_*.c edit/test_*.c formula/test_*.c; do
  bin="${src%.c}"
  if [ ! -x "$bin" ]; then echo "missing $bin (build.sh bug)" >&2; missing=1; continue; fi
  out=$("$bin" 2>&1 || true)
  if line=$(printf '%s\n' "$out" | grep -E '^[0-9]+ tests, [0-9]+ failures' | tail -1); then
    n=$(printf '%s' "$line" | awk '{print $1}'); f=$(printf '%s' "$line" | awk '{print $3}')
    passed=$((passed+n-f)); failed=$((failed+f))
  else
    echo "no unity summary from $bin" >&2; missing=1
  fi
done

[ "$missing" -eq 0 ] || failed=$((failed+1))
cd "$SRC"
emit_ctrf "libxlsx-ctest-unity" "$passed" "$failed" "$skipped"
