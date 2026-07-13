#!/usr/bin/env bash
#
# mayhem/test.sh — RUN caddy's OWN upstream Go test suite (`go test ./...`) and map
# the result to a CTRF summary. This is the authors' functional/behavioral suite
# (table-driven known-answer tests, golden comparisons, and caddytest integration
# tests) — NOT a hand-rolled oracle. A no-op/exit(0) sabotage of the fuzzed program
# makes the pre-built test binaries exit before asserting, so the suite regresses
# (fewer PASS lines / non-zero rc) and this oracle FAILS — i.e. it is behavioral.
#
# Go compiles test binaries on demand, so we invoke `go test` here (the port-go
# sanctioned pattern); the module cache was populated by mayhem/build.sh.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"

export GOFLAGS="${GOFLAGS:--mod=mod}"
export GOPROXY="${GOPROXY:-file://$(go env GOMODCACHE)/cache/download,https://proxy.golang.org,direct}"

cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
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

LOG=/tmp/caddy-test.log
# Entire upstream suite. -short matches caddy CI's `go test -race -short ./...`
# (skips long-running cases); -v prints one --- PASS/FAIL/SKIP line per (sub)test;
# -count=1 disables the test cache so results reflect THIS build (required for the
# behavioral/sabotage oracle — a cached "ok" would hide a neutered program).
go test -short -count=1 -v ./... 2>&1 | tee "$LOG"
rc=${PIPESTATUS[0]}

passed=$(grep -cE '^[[:space:]]*--- PASS:' "$LOG" || true)
failed=$(grep -cE '^[[:space:]]*--- FAIL:' "$LOG" || true)
skipped=$(grep -cE '^[[:space:]]*--- SKIP:' "$LOG" || true)
# A crashed/panicked/failed-to-build runner may print no per-test FAIL lines —
# count it as a failure so the oracle never silently passes on a broken suite.
if [ "$rc" -ne 0 ] && [ "$failed" -eq 0 ]; then
  failed=1
fi

emit_ctrf "go-test" "$passed" "$failed" "$skipped"
