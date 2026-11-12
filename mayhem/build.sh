#!/usr/bin/env bash
#
# mayhem/build.sh — builds (1) the libxlsx fuzz harnesses against a sanitized, SanCov-instrumented
# build of the bundled library (library/libxlsx) and (2) libxlsx's own test suite with NORMAL flags.
# Runs in the commit image as `mayhem` in /mayhem; re-runnable and offline (apt -dev packages only).
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
: "${SRC:=/mayhem}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"
LIB="$SRC/library/libxlsx"
B="$SRC/mayhem/build"          # intermediate objects; `build` is gitignored upstream
mkdir -p "$B/obj" "$B/std"

# ---------------------------------------------------------------------------------------------
# 1) The project, sanitized + SanCov-instrumented (flags mirror config.m4: bundled md5/minizip/
#    tmpfileplus/dtoa; system expat + zlib from apt).
# ---------------------------------------------------------------------------------------------
LIBFLAGS="$SANITIZER_FLAGS -fsanitize=fuzzer-no-link $DEBUG_FLAGS -O1"
LIBDEFS="-DNOCRYPT -DNOUNCRYPT -DXML_POOR_ENTROPY -DUSE_DTOA_LIBRARY"
LIBINC="-I$LIB/include -I$LIB/internal -I$LIB/src -I$LIB/third_party/minizip"

srcs=("$LIB"/src/*.c
      "$LIB"/third_party/minizip/ioapi.c "$LIB"/third_party/minizip/unzip.c "$LIB"/third_party/minizip/zip.c
      "$LIB"/third_party/minizip/mztools.c
      "$LIB"/third_party/tmpfileplus/tmpfileplus.c
      "$LIB"/third_party/dtoa/emyg_dtoa.c
      "$LIB"/third_party/md5/md5.c)

printf '%s\n' "${srcs[@]}" | xargs -P "$MAYHEM_JOBS" -I{} bash -c '
  f="{}"; o="$0/obj/$(basename "${f%.c}").o"
  $CC $1 $2 $3 -c "$f" -o "$o"' "$B" "$LIBFLAGS" "$LIBDEFS" "$LIBINC"

rm -f "$B/libxlsx_fuzz.a"
ar rcs "$B/libxlsx_fuzz.a" "$B"/obj/*.o

# ---------------------------------------------------------------------------------------------
# 2) Harnesses: libFuzzer binary + non-fuzzer standalone reproducer; LSan hook linked into both.
# ---------------------------------------------------------------------------------------------
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c "$SRC/mayhem/lsan_off.cc" -o "$B/lsan_off.o"
$CC -c $DEBUG_FLAGS "$STANDALONE_FUZZ_MAIN" -o "$B/standalone_main.o"

LINKLIBS="$B/libxlsx_fuzz.a -Wl,-Bstatic -lexpat -Wl,-Bdynamic -lz -lm"
for h in fuzz_reader fuzz_edit fuzz_formula; do
  $CC $SANITIZER_FLAGS $DEBUG_FLAGS -O1 $LIBINC "$SRC/mayhem/harnesses/$h.c" -c -o "$B/$h.o"
  $CC $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE "$B/$h.o" "$B/lsan_off.o" $LINKLIBS -o "$SRC/$h"
  $CC $SANITIZER_FLAGS $DEBUG_FLAGS "$B/$h.o" "$B/standalone_main.o" "$B/lsan_off.o" $LINKLIBS -o "$SRC/$h-standalone"
done

# ---------------------------------------------------------------------------------------------
# 3) libxlsx's own test suite (writer/ctest, reader/integration/edit/formula unity), NORMAL flags,
#    built by upstream's Makefile against system expat (the bundled one is a git submodule).
# ---------------------------------------------------------------------------------------------
cd "$LIB/test"
tests=$(ls reader/test_*.c integration/test_*.c edit/test_*.c formula/test_*.c | sed 's/\.c$//')
env -u CFLAGS -u LDFLAGS -u CPPFLAGS \
  CFLAGS="$COVERAGE_FLAGS" LDFLAGS="$COVERAGE_FLAGS" \
  make -j"$MAYHEM_JOBS" EXPAT_SRCS= EXPAT_DIR=/usr/include LIBS_O="-lz -lexpat -lm" \
    writer/test_all reader-fixtures edit-fixtures $tests
