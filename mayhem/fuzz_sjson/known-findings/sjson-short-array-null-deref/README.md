# `sjson::parse_vector2/3/4`, `parse_quaternion`, `parse_matrix4x4`: no array-length check

`src/core/json/sjson.cpp:596-670`: each accessor parses the array and then indexes `arr[0]`, `arr[1]`, ... with no length check, so a short array (`[]`, `[1]`) dereferences NULL (`Array<char const*>::operator[]`, `array.inl:285`) or reads past the array.

- **Cause:** the accessors assume the caller already knows the array has the documented shape (`[x, y]`, `[x, y, z]`, ...); `CE_ASSERT` bounds checks are compiled out of release builds.
- **Why the harness doesn't hit it any more:** `fuzz_sjson` only calls an accessor on an array of the size it documents (2, 3, 4, 4 and 16), as a caller that knows its schema does. A harness that called all of them on every array stopped on `[]` at the first input and hid deeper SJSON coverage.
- **Reproducer:** `input.sjson` is `[]` as the value of a key, e.g. `a = []`, run through a build that calls `sjson::parse_vector2(arr)` directly (the fuzz target no longer does).
- **Impact:** crash on SJSON whose vector/matrix fields have the wrong length, e.g. in resource compilers reading user data.
- **Upstream fix:** check `array::size(arr)` against the expected length and report an error before indexing.
