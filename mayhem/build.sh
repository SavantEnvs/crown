#!/usr/bin/env bash
#
# mayhem/build.sh — build crown's fuzz harnesses (sanitized) and its unit-test oracle (normal flags).
#
# Crown's full engine needs bgfx/bullet/openal/X11/wayland and the genie toolchain, none of which the
# fuzzed code (core/ + the expression language) depends on. So this builds just those sources, the
# same way the engine's own build does (same defines, no per-file edits), into two static libraries:
#   build/mayhem/san/libcrown_fuzz.a   release defines, $SANITIZER_FLAGS + fuzzer-no-link coverage
#   build/mayhem/test/libcrown_test.a  CROWN_DEBUG=1 (enables the engine's unit tests), normal flags
# Both live under /build, which upstream's .gitignore already covers (SPEC §6.2 item 16).
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
OUT="$SRC/build/mayhem"
mkdir -p "$OUT/san" "$OUT/test"

INC="-I$SRC/src -I$SRC/3rdparty/bx/include -I$SRC/3rdparty/stb -I$SRC/3rdparty/dr_libs"

# Sources shared by both builds: crown's core library (Linux backends only), the expression language,
# logging, and the stb_sprintf implementation (normally supplied by device/main_linux.cpp).
core_sources() {
	(cd "$SRC/src"
	 ls core/*.cpp core/*/*.cpp resource/expression_language.cpp device/log.cpp device/console_server.cpp \
		| grep -v -E 'windows|apk|html5|http_file_native|file_monitor_noop|filesystem_http|http_linux|unit_tests')
	echo "mayhem/stb_impl.cc"
}

# compile_all <outdir> <flags> < file-list   (paths relative to src/, or mayhem/*.cc)
compile_all() {
	local dir="$1" flags="$2" f o
	while read -r f; do
		case "$f" in
		mayhem/*) o="$dir/$(basename "${f%.*}").o"; echo "$CXX $flags -c $SRC/$f -o $o" ;;
		*)        o="$dir/$(echo "${f%.*}" | tr / _).o"; echo "$CXX $flags -c $SRC/src/$f -o $o" ;;
		esac
	done | xargs -P "$MAYHEM_JOBS" -I{} bash -c '{}'
}

# 1) Sanitized + coverage-instrumented library for the fuzz targets. Release defines, as shipped:
#    CE_ASSERT is compiled out, so a malformed input must not read out of bounds to survive.
# Two UBSan checks are relaxed because benign upstream idioms hit them on essentially every input and, with
# halting sanitizers, would stop every target before it explores anything. ASan and the rest of UBSan stay on.
#  - nonnull-attribute: Array::set_capacity() does memcpy(new, NULL, 0) on the first growth of an empty array.
#  - alignment: TempAllocator::allocate() stores a void* into a chunk the backing allocator only 4-aligns, and
#    stb_sprintf deliberately does unaligned u32 stores (both are fine on x86).
SAN_FLAGS="-std=c++17 -O1 -ffunction-sections -fdata-sections $SANITIZER_FLAGS -fno-sanitize=nonnull-attribute,alignment $DEBUG_FLAGS -fsanitize=fuzzer-no-link $INC"
rm -f "$OUT"/san/*.o "$OUT/san/libcrown_fuzz.a"
core_sources | compile_all "$OUT/san" "$SAN_FLAGS"
ar rcs "$OUT/san/libcrown_fuzz.a" "$OUT"/san/*.o

$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c "$SRC/mayhem/lsan_off.cc" -o "$OUT/san/lsan_off.o.keep"
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o "$OUT/san/standalone_main.o.keep"

# 2) Each harness twice: libFuzzer binary + standalone run-once reproducer.
for h in fuzz_sjson fuzz_expression_language fuzz_text; do
	$CXX $SAN_FLAGS $LIB_FUZZING_ENGINE "$SRC/mayhem/$h.cc" "$OUT/san/libcrown_fuzz.a" \
		"$OUT/san/lsan_off.o.keep" -Wl,--gc-sections -lpthread -o "$OUT/$h"
	$CXX $SAN_FLAGS "$SRC/mayhem/$h.cc" "$OUT/san/standalone_main.o.keep" "$OUT/san/libcrown_fuzz.a" \
		"$OUT/san/lsan_off.o.keep" -Wl,--gc-sections -lpthread -o "$OUT/$h-standalone"
done

# 3) Test oracle, NORMAL flags (no sanitizers): the engine's own unit-test suite + a known-answer probe.
TEST_FLAGS="-std=c++17 -O2 -ffunction-sections -DCROWN_DEBUG=1 -DBX_CONFIG_DEBUG=1 $COVERAGE_FLAGS $INC"
rm -f "$OUT"/test/*.o "$OUT/test/libcrown_test.a"
{ core_sources; echo "core/unit_tests.cpp"; echo "resource/lua_resource.cpp"; } | compile_all "$OUT/test" "$TEST_FLAGS"
ar rcs "$OUT/test/libcrown_test.a" "$OUT"/test/*.o
$CXX $TEST_FLAGS "$SRC/mayhem/unit_tests_main.cc" "$OUT/test/libcrown_test.a" $COVERAGE_FLAGS \
	-Wl,--gc-sections -lpthread -o "$OUT/unit_tests"
$CXX $TEST_FLAGS "$SRC/mayhem/kat_probe.cc" "$OUT/test/libcrown_test.a" $COVERAGE_FLAGS \
	-Wl,--gc-sections -lpthread -o "$OUT/kat_probe"

ls -l "$OUT"/fuzz_* "$OUT"/unit_tests "$OUT"/kat_probe
