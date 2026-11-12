# Benchmark

Measures how often the letter ScreenPulse would signal matches the expected answer, on
100 generated screenshots of quiz-style web pages (macOS only; needs Google Chrome).

```bash
swiftc -O benchmark/crop.swift -o benchmark/crop -framework AppKit
node benchmark/make-images.mjs
node benchmark/run-benchmark.mjs hel app 2
node benchmark/summary.mjs
```

The question bank, manifest fields and crop names (`centreret`, `skub`, `hel`) are Danish
test data carried over from the predecessor project. The files in `results/` were produced
with the original Danish prompt (`prompt-da.txt`, prompt name `ny`); the current English
prompt (`app`) has not been benchmarked yet.
