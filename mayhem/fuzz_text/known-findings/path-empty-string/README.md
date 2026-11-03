# `path::has_trailing_separator("")` / `path::reduce("")` read out of bounds

`src/core/filesystem/path.cpp`:

```cpp
bool has_trailing_separator(const char *path)
{
	CE_ENSURE(NULL != path);
	return path[strlen32(path) - 1] == PATH_SEPARATOR;   // strlen32("") - 1 wraps to 0xFFFFFFFF
}
```

- **Cause:** `strlen32` returns `u32`; for an empty string `0 - 1` wraps and the read lands ~4 GiB past
  the buffer (SEGV, or a heap-buffer-overflow read under ASan). `path::reduce("")` reaches the same
  line, because the cleaned string is empty when the input is empty.
- **Reproducer:** `empty-input` (zero bytes). `fuzz_text-standalone empty-input` aborts with
  `SEGV ... path.cpp:111:10 in crown::path::has_trailing_separator`.
- **Impact:** a crash on a trivially reachable input (empty path), with a wild read.
- **Upstream fix (one line):** `const u32 len = strlen32(path); return len > 0 && path[len - 1] == PATH_SEPARATOR;`
- **Harness:** `fuzz_text` does not call these two functions, because the empty input would otherwise end
  every run at the first execution and nothing else in the target would be fuzzed.
