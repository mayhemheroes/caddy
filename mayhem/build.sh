#!/usr/bin/env bash
#
# mayhem/build.sh — build caddy's go-fuzz harness as a sanitized libFuzzer binary
# (OSS-Fuzz Go path: go-fuzz-build -libfuzzer + clang link).
#
# The historical Mayhem target is `fuzz-extract-front-matter` — the
# FuzzExtractFrontMatter harness over caddy's front-matter parser
# (modules/caddyhttp/templates/frontmatter_fuzz.go). Preserve that target name
# for corpus/defect continuity.
#
# AIR-GAPPED CONTRACT (SPEC §6.5): the PATCH tier re-runs THIS script OFFLINE.
# GOPROXY resolves from the in-image module cache first, network last.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
# OSS-Fuzz Go path is ASan-only for the libFuzzer link.
: "${SANITIZER_FLAGS=-fsanitize=address}"
: "${MAYHEM_JOBS:=$(nproc)}"
# DWARF < 4 contract (§6.2 item 10): gc emits DWARF4; the clang-compiled cgo shim
# would land DWARF-5 first — thread -gdwarf-3 through CGO and the final link.
: "${GO_DEBUG_FLAGS:=-g -gdwarf-3}"
export GOEXPERIMENT=nodwarf5
export CGO_CFLAGS="${CGO_CFLAGS:-$GO_DEBUG_FLAGS}" CGO_CXXFLAGS="${CGO_CXXFLAGS:-$GO_DEBUG_FLAGS}"
export CC CXX LIB_FUZZING_ENGINE SANITIZER_FLAGS MAYHEM_JOBS GO_DEBUG_FLAGS

# Resolve modules offline-first from the in-image cache; network only as a fallback.
export GOFLAGS="${GOFLAGS:--mod=mod}"
export GOPROXY="${GOPROXY:-file://$(go env GOMODCACHE)/cache/download,https://proxy.golang.org,direct}"

cd "$SRC"
go version

# go-fuzz-build needs go-fuzz-dep on the module graph (resolves from cache offline).
go get github.com/dvyukov/go-fuzz/go-fuzz-dep

HARNESS_PKG="./modules/caddyhttp/templates"
FUZZ_FUNC="FuzzExtractFrontMatter"
TARGET="fuzz-extract-front-matter"   # preserve the old Mayhem target name
# go-fuzz's rewriter mishandles a compiler directive in filippo.io/bigmod's
# assembly stub (nat_asm.go: "misplaced compiler directive"); leave that pure-Go
# crypto dep uninstrumented — it is not on the front-matter parse path.
PRESERVE="filippo.io/bigmod"

mkdir -p "$SRC/mayhem-build"
echo "=== building $TARGET (go-fuzz-build -libfuzzer -func $FUZZ_FUNC) ==="
go-fuzz-build -libfuzzer -func "$FUZZ_FUNC" -preserve "$PRESERVE" -o "$SRC/mayhem-build/$TARGET.a" "$HARNESS_PKG"
$CXX $SANITIZER_FLAGS $LIB_FUZZING_ENGINE $GO_DEBUG_FLAGS "$SRC/mayhem-build/$TARGET.a" -o "/mayhem/$TARGET"
echo "built /mayhem/$TARGET"

echo "build.sh complete"
