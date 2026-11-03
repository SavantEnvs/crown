# `expression_language::compile()` / `run()` on malformed function calls

One cause, 8 defects in the 300s run (frames below are the first application frame of each):

| Frame | Count | Side |
|---|---|---|
| `src/resource/expression_language.inl:10` (`pop()`) | 5 | `compile()` and `run()` |
| `src/resource/expression_language.cpp:331`, `:332` (`fold_constants()`) | 1 + 1 | `compile()` |
| `src/resource/expression_language.cpp:63` (`length()`, via `match()` / `default_compute_function()` / `run()`) | 1 | `run()` |

- **Cause:** a malformed call such as `match(*cos(a) + ...)` leaves too few operands for the function's arity. `CE_ASSERT(i >= arity, "Too few arguments to function")` is the only guard. `fold_constants()` then indexes `rpl[i - j - 1]` below zero and `pop()` underflows the stack in `compile()`. `run()` pops the same missing operands for `OP_MATCH`, so `match()` and `length()` read the float stack out of bounds.
- **Reproducer:** `input.expr` (SEGV in ASan).
- **Where it is reachable:** `CE_ASSERT` is live exactly when `CROWN_DEBUG` is set (`error.inl`), and `compile()` is only built with `CROWN_CAN_COMPILE` (`CROWN_DEBUG || CROWN_DEVELOPMENT`, `config.h`). Every engine build that calls `compile()` therefore aborts on these inputs at the assert. The out-of-bounds reads happen only in the release-define fuzz build, where the assert is compiled out. In shipped builds `run()` only sees bytecode that `compile()` produced.
- **Upstream fix:** make the arity check a real error return (not an assert) in `compile()` before `fold_constants()` and `run()`.
