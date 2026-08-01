# ToonEx Performance Benchmarks
#
# Unified benchmark suite for encoding, decoding, and roundtrip operations.
# Uses centralized test data from bench/data.exs for consistency.
#
# Run with: MIX_ENV=dev mix run bench/performance.exs

require Benchee

# Load centralized test data
Code.require_file("data.exs", __DIR__)

# ============================================================================
# Benchmark Configuration
# ============================================================================

# Elixir data inputs (for encoding and roundtrip)
elixir_inputs = BenchData.encode_inputs()

# TOON strings (for ToonEx.decode!)
toon_inputs = Enum.into(elixir_inputs, %{}, fn {k, v} -> {k, BenchData.toon_string(v)} end)

# JSON strings (for JSON.decode!) - limit to key inputs
json_inputs = Enum.into(elixir_inputs, %{}, fn {k, v} -> {k, JSON.encode!(v)} end)
|> Map.take(["small_object", "medium_object", "large_object", "primitive_array_100", "tabular_array_50", "tabular_array_500", "list_array_20", "string_with_escapes", "empty_object", "empty_array"])

# Roundtrip inputs (Elixir data) - focus on core scenarios
roundtrip_inputs = Map.take(BenchData.roundtrip_inputs(), ["small_object", "medium_object", "large_object", "primitive_array_100", "tabular_array_50", "tabular_array_500"])

# ============================================================================
# Build flat inputs map - each key is a unique test case
# ============================================================================

# Encoding inputs: Elixir data -> "encode_<name>"
encode_inputs = Enum.into(elixir_inputs, %{}, fn {k, v} -> {"encode_#{k}", v} end)

# ToonEx decoding inputs: TOON string -> "decode_toon_<name>"
decode_toon_inputs = Enum.into(toon_inputs, %{}, fn {k, v} -> {"decode_toon_#{k}", v} end)

# JSON decoding inputs: JSON string -> "decode_json_<name>"
decode_json_inputs = Enum.into(json_inputs, %{}, fn {k, v} -> {"decode_json_#{k}", v} end)

# Roundtrip inputs: Elixir data -> "roundtrip_<name>"
roundtrip_inputs_map = Enum.into(roundtrip_inputs, %{}, fn {k, v} -> {"roundtrip_#{k}", v} end)

# ============================================================================
# Run Benchmarks - Separate runs for different input types
# ============================================================================

# ---- Encoding Benchmarks ----
IO.puts("\n" <> String.duplicate("=", 80))
IO.puts("ENCODING BENCHMARKS")
IO.puts(String.duplicate("=", 80))

Benchee.run(
  %{
    "ToonEx.encode!" => fn input -> ToonEx.encode!(input) end,
    "JSON.encode!" => fn input -> JSON.encode!(input) end
  },
  inputs: Enum.into(elixir_inputs, %{}, fn {k, v} -> {"encode_#{k}", v} end),
  time: 3,
  memory_time: 1,
  reduction_time: 1,
  formatters: [
    {Benchee.Formatters.Console, comparisons: true, extended_statistics: true, column_width: 80}
  ],
  print: [fast_warning: false]
)

# ---- Decoding TOON ----
IO.puts("\n" <> String.duplicate("=", 80))
IO.puts("TOON DECODING BENCHMARKS")
IO.puts(String.duplicate("=", 80))

Benchee.run(
  %{
    "ToonEx.decode!" => fn input -> ToonEx.decode!(input) end
  },
  inputs: Enum.into(toon_inputs, %{}, fn {k, v} -> {"decode_toon_#{k}", v} end),
  time: 3,
  memory_time: 1,
  reduction_time: 1,
  formatters: [
    {Benchee.Formatters.Console, comparisons: true, extended_statistics: true, column_width: 80}
  ],
  print: [fast_warning: false]
)

# ---- Decoding JSON ----
IO.puts("\n" <> String.duplicate("=", 80))
IO.puts("JSON DECODING BENCHMARKS")
IO.puts(String.duplicate("=", 80))

Benchee.run(
  %{
    "JSON.decode!" => fn input -> JSON.decode!(input) end
  },
  inputs: Enum.into(json_inputs, %{}, fn {k, v} -> {"decode_json_#{k}", v} end),
  time: 3,
  memory_time: 1,
  reduction_time: 1,
  formatters: [
    {Benchee.Formatters.Console, comparisons: true, extended_statistics: true, column_width: 80}
  ],
  print: [fast_warning: false]
)

# ---- Roundtrip ----
IO.puts("\n" <> String.duplicate("=", 80))
IO.puts("ROUNDTRIP BENCHMARKS")
IO.puts(String.duplicate("=", 80))

Benchee.run(
  %{
    "ToonEx roundtrip" => fn input ->
      input
      |> ToonEx.encode!()
      |> ToonEx.decode!()
    end,
    "JSON roundtrip" => fn input ->
      input
      |> JSON.encode!()
      |> JSON.decode!()
    end
  },
  inputs: Enum.into(roundtrip_inputs, %{}, fn {k, v} -> {"roundtrip_#{k}", v} end),
  time: 3,
  memory_time: 1,
  reduction_time: 1,
  formatters: [
    {Benchee.Formatters.Console, comparisons: true, extended_statistics: true, column_width: 80}
  ],
  print: [fast_warning: false]
)

# ============================================================================
# Size Comparison Report (TOON vs JSON)
# ============================================================================

IO.puts("\n" <> String.duplicate("=", 80))
IO.puts("TOON vs JSON Size Comparison")
IO.puts(String.duplicate("=", 80))

size_tests = [
  {"Small Object", BenchData.small_object()},
  {"Medium Object", BenchData.medium_object()},
  {"Large Object", BenchData.large_object()},
  {"Deeply Nested", BenchData.deeply_nested()},
  {"Primitive Array (100)", BenchData.primitive_array_100()},
  {"Tabular Array (50)", BenchData.tabular_array_50()},
  {"Tabular Array (500)", BenchData.tabular_array_500()},
  {"List Array (20)", BenchData.list_array_20()},
  {"Empty Object", BenchData.empty_object()},
  {"Empty Array", BenchData.empty_array()}
]

Enum.each(size_tests, fn {name, data} ->
  toon_size = byte_size(ToonEx.encode!(data))
  json_size = byte_size(JSON.encode!(data))
  savings = ((1 - toon_size / json_size) * 100) |> Float.round(1)

  IO.puts("\n#{name}:")
  IO.puts("  TOON: #{toon_size} bytes")
  IO.puts("  JSON: #{json_size} bytes")
  IO.puts("  Savings: #{savings}%")
end)