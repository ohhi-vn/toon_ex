# TOON Parser Optimization

## Overview

This document describes the high-performance parser implementation that achieves
significant performance improvement through pure binary pattern matching and
zero-copy slicing.

## Performance Results

Benchmark results comparing original (V1) vs optimized (V2) parser:

| Test Case | V1 Time | V2 Time | Speedup |
|-----------|---------|---------|---------|
| Simple objects | 17 µs | 3 µs | **5.7x** |
| Nested structures | 43 µs | 13 µs | **3.3x** |
| Arrays | 48 µs | 24 µs | **2.0x** |
| Large (100 items) | 1379 µs | 358 µs | **3.9x** |

Run the benchmark yourself:
```bash
mix run benchmarks/parser_comparison.exs
```

## Optimization Strategy

The optimized parser (`ToonEx.Decode.Fast.Decoder`) uses pure binary pattern
matching with no external parsing libraries (NimbleParsec) in hot paths.

### Phase 1: Line Classification

Each line is classified upfront into one of four types:
- `:primitive` - Standalone values or key-value pairs
- `:array` - Array headers (lines ending with `:` or containing `[`)
- `:object` - Object headers (keys with nested content)
- `:array_item` - Lines starting with `- `

This eliminates redundant pattern matching during recursive descent.

### Phase 2: Recursive Descent with Fast Path

The pre-classified lines are processed using recursive descent, with `:primitive`
as the first (fastest) case in pattern matching.

### Zero-Copy Slicing

The decoder uses `binary_part/3` to create sub-binary references instead of
copying data. This is O(1) — it creates a reference to the original binary
rather than allocating and copying.

### Control Character Escaping

String encoding uses a Jason-style chunk-based approach with `binary_part/3`
to reference safe chunks of the original string without copying. Only escape
sequences are newly allocated. Control characters (U+0000–U+001F, U+007F) are
escaped as `\uXXXX`.

## Current Status

The `Fast.Decoder` is the default and only decoder used by `ToonEx.Decode`.
The original parser (`ToonEx.Decode.Parser`) and structural parsers
(`ToonEx.Decode.StructuralParser`, `ToonEx.Decode.StructuralParserV2`) are
retained for reference but are no longer used in production paths.

## Files

- Fast decoder: `lib/toon_ex/decode/fast/decoder.ex`
- Original parser: `lib/toon_ex/decode/structural_parser.ex`
- Benchmark script: `benchmarks/parser_comparison.exs`
