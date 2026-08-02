# BTOON decode benchmark
# Compares decoding of BTOON binary against TOON text and JSON.
# Run with: mix run bench/btoon/decode.exs

Code.require_file("data.exs", __DIR__)

inputs =
  BtoonBenchData.datasets()
  |> Map.new(fn {label, data} ->
    {label,
     %{
       btoon: BtoonBenchData.btoon_binary(data),
       toon: BtoonBenchData.toon_string(data),
       json: BtoonBenchData.json_string(data)
     }}
  end)

Benchee.run(
  %{
    "ToonEx.Btoon.decode!" => fn %{btoon: binary} -> ToonEx.Btoon.decode!(binary) end,
    "ToonEx.decode!" => fn %{toon: text} -> ToonEx.decode!(text) end,
    "Jason.decode!" => fn %{json: text} -> Jason.decode!(text) end
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
