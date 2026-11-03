# `sjson::skip_string()` reads past the NUL after a trailing backslash

`src/core/json/sjson.cpp:89`, the loop `while (*++json)` in `skip_string()`, reached from `skip_value()` (`sjson.cpp:173`) and `parse_root_object()` (`sjson.cpp:496`).

- **Cause:** when the input ends inside a quoted string with a backslash as its last byte, the `'\\'` branch does `++json` to skip the escaped character and lands on the terminating NUL. The loop's `++json` then steps past it and reads the bytes after the buffer. The `fatal("Bad string")` after the loop is compiled out of release builds.
- **Reproducer:** `input.sjson` (an unterminated string ending in `\`; heap-buffer-overflow read in ASan; the harness passes a NUL-terminated copy).
- **Impact:** out-of-bounds heap read on untrusted SJSON.
- **Upstream fix:** after skipping the escaped character, stop if `*json == '\0'` (return NULL / report "Bad string").
