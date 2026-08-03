# BTOON roundtrip benchmark
# Compares encode+decode roundtrip performance across formats.
# Run with: mix run bench/btoon/roundtrip.exs

Code.require_file("data.exs", __DIR__)

inputs =
  BtoonBenchData.datasets()
  |> Map.new(fn {label, data} -> {label, data} end)

Benchee.run(
  %{
    "Btoon roundtrip" => fn input ->
      input |> Btoon.encode!() |> ToonEx.Btoon.decode!()
    end,
    "ToonEx roundtrip" => fn input ->
      input |> ToonEx.encode!() |> ToonEx.decode!()
    end,
    "Jason roundtrip" => fn input ->
      input |> Jason.encode!() |> Jason.decode!()
    end
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
