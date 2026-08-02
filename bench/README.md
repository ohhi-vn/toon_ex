# ToonEx Benchmarks

Performance benchmarks comparing ToonEx (TOON format) against standard JSON encoding/decoding.

## Quick Start

Run all benchmarks:

```bash
# Run individual benchmarks
mix run bench/encode/small_size.exs
mix run bench/encode/medium_size.exs
mix run bench/encode/large_size.exs

mix run bench/decode/small_size.exs
mix run bench/decode/medium_size.exs
mix run bench/decode/large_size.exs

# Compare token/byte efficiency
mix run bench/size/token_count.exs

# BTOON benchmarks
mix run bench/btoon/encode.exs
mix run bench/btoon/decode.exs
mix run bench/btoon/roundtrip.exs
mix run bench/btoon/size.exs
```

## BTOON Benchmarks (`bench/btoon/`)

Compares the BTOON binary codec (`ToonEx.Btoon`) against the TOON text format
(`ToonEx`) and standard JSON (`Jason`).

- **encode**: BTOON binary vs TOON text vs JSON encoding
- **decode**: BTOON binary vs TOON text vs JSON decoding
- **roundtrip**: Encode + decode in a single pass for each format
- **size**: Byte-size comparison of BTOON vs TOON vs JSON output

## Benchmark Categories

### Encoding Benchmarks (`bench/encode/`)

Tests encoding performance from Elixir data structures to TOON/JSON strings.

- **Small** (~50 bytes): Simple flat object with 2 fields
- **Medium** (~200 bytes): Nested object with inline array
- **Large** (~5KB): 50-row tabular array with metadata

### Decoding Benchmarks (`bench/decode/`)

Tests decoding performance from TOON/JSON strings back to Elixir data structures.

- **Small** (~50 bytes): Simple flat object
- **Medium** (~200 bytes): Nested object with inline array
- **Large** (~5KB): 100-row tabular array with metadata

### Size Comparison (`bench/size/`)

Compares byte sizes (proxy for token count) between TOON and JSON output.

## Configuration

Each benchmark uses Benchee with:
- **Time**: 5 seconds per scenario
- **Memory time**: 2 seconds for memory measurements
- **Formatters**: Console output with comparisons + memory formatter
- **Print**: Fast warning disabled for cleaner output

## Interpreting Results

- **ips** (iterations per second): Higher is better
- **average**: Lower is better (time per iteration)
- **memory**: Lower is better (bytes allocated per iteration)
- **reduction**: Percentage size reduction of TOON vs JSON
