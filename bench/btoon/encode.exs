# BTOON encode benchmark
# Compares BTOON binary encoding against TOON text and JSON.
# Run with: mix run bench/btoon/encode.exs

Code.require_file("data.exs", __DIR__)

inputs =
  BtoonBenchData.datasets()
  |> Map.new(fn {label, data} -> {label, data} end)

Benchee.run(
  %{
    "Btoon.encode!" => fn input -> ToonEx.Btoon.encode!(input) end,
    "ToonEx.encode!" => fn input -> ToonEx.encode!(input) end,
    "JSON.encode!" => fn input -> JSON.encode!(input) end
  },
  inputs: inputs,
  time: 5,
  memory_time: 2,
  formatters: [
    {Benchee.Formatters.Console, comparisons: true}
  ],
  print: [
    fast_warning: false
  ]
)
