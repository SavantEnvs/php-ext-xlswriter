# UBSan: double -> long long cast out of range (formula.c:525)

`ub-double-to-int64.bin` (a formula string; `./fuzz_formula-standalone ub-double-to-int64.bin`) makes
`library/libxlsx/src/formula.c:525` evaluate `(long long)d` with `d = 2e31`:
"runtime error: 2e+31 is outside the range of representable values of type 'long long'".
The range test `fabs(d) < 1e15` comes after the cast in the same condition, so it cannot protect it.
Upstream fix: test `fabs(d) < 1e15` first (`fabs(d) < 1e15 && d == (double)(long long)d`).
Not a memory-safety bug; it halts the UBSan build.
