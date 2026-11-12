# Unbounded allocation from a zip entry's declared size (source_package.c:589)

`oom-source-package-read-entry.xlsx` (`./fuzz_edit-standalone oom-source-package-read-entry.xlsx`, or with
`-malloc_limit_mb=2048` under libFuzzer) makes `lxlsx_source_package_read_entry`
(`library/libxlsx/src/source_package.c:589`) call `malloc(uncompressed_size + 1)` with a ~2.5 GB size taken
straight from the zip header, reached via `lxlsx_edit_save_as` -> `get_dirty_sheet` (edit.c:1873).
The only cap is `UINT_MAX`, so a ~3 KB file can request up to 4 GB. Upstream fix: cap the entry size
(or grow the buffer while inflating) instead of trusting the header.
