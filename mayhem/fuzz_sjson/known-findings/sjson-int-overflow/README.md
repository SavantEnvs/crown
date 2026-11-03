# `sjson::parse_int()` / `parse_float()`: out-of-range number casts

`src/core/json/sjson.cpp:351` casts the parsed `f64` straight to `s32` (`return (s32)parse_number(json);`).

- **Cause:** a number outside the `s32` range makes the cast undefined behavior (UBSan halts it). Only a `fatal()` that is compiled out of release builds guards the float variant.
- **Reproducer:** `input.sjson` (an SJSON document with a very long run of digits in `size`). The fuzz target calls `parse_int` on every scalar it finds.
- **Impact:** undefined behavior reachable from any SJSON value that is read as an int.
- **Upstream fix:** range-check the `f64` against `INT32_MIN/INT32_MAX` before the cast and return an error/0 when it is out of range.
