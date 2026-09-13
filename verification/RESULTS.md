# Local verification

Verified on 2026-09-13, macOS arm64.

- Moon compiler: v0.10.12+1634b282e (2026-09-07).
- Moon build tool: 0.1.20260904 (94521db).
- Node.js: v22.22.2; Python: 3.14.6.
- Official toolchain archive SHA-256 verified before use.

`python3 scripts/verify.py` passed all stages:

1. `moon fmt --check` — passed.
2. `moon check` — passed, no warnings.
3. `moon test` — 20 tests passed, 0 failed.
4. `moon build --target js --release` — passed.
5. `python3 tests/e2e.py` — 79 CLI checks passed, including 60 independently computed randomized CSV/decimal/provenance comparisons (seed 20260913).

The CLI checks cover example output, exact physical lines, both directions of missing records, duplicate groups, decimal differences, deterministic output, unchanged input hashes, usage errors, invalid UTF-8, ordinary-file restrictions including a FIFO on this OS, and byte/column/record limits.

An initial oracle mismatch came from Python universal-newline conversion in the test harness. The oracle now decodes original bytes before passing them to csv.reader; MoonLedger preserves CRLF inside quoted values as intended. No expected product output was changed to hide the mismatch.

This is local implementation evidence, not proof of official contest acceptance, award eligibility or payment. Other compilation targets and operating systems are not validated by this run.
