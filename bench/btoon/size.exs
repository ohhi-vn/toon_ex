# BTOON vs TOON vs JSON size comparison
# Measures byte size as a proxy for token count.
# Run with: mix run bench/btoon/size.exs

Code.require_file("data.exs", __DIR__)

IO.puts("\n=== BTOON vs TOON vs JSON Size Comparison ===\n")

Enum.each(BtoonBenchData.datasets(), fn {label, data} ->
  btoon = BtoonBenchData.btoon_binary(data)
  toon = BtoonBenchData.toon_string(data)
  json = BtoonBenchData.json_string(data)

  btoon_size = byte_size(btoon)
  toon_size = byte_size(toon)
  json_size = byte_size(json)

  IO.puts("#{label}:")
  IO.puts("  BTOON: #{btoon_size} bytes")
  IO.puts("  TOON:  #{toon_size} bytes")
  IO.puts("  JSON:  #{json_size} bytes")
  IO.puts(
    "  BTOON vs JSON: #{Float.round((1 - btoon_size / json_size) * 100, 1)}% reduction"
  )

  IO.puts("  BTOON vs TOON: #{Float.round((1 - btoon_size / toon_size) * 100, 1)}% reduction")
  IO.puts("")
end)
