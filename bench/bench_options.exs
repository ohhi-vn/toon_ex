# Benchmark for options validation caching (O2 improvement)
# Run with: MIX_ENV=dev mix run bench/bench_options.exs

defmodule BenchOptions do
  @moduledoc false

  def run do
    # Test default options validation (should hit cache)
    Benchee.run(
      %{
        "validate default encode opts (cached)" => fn ->
          ToonEx.Encode.Options.validate!([])
        end,
        "validate default decode opts (cached)" => fn ->
          ToonEx.Decode.Options.validate!([])
        end,
        "validate custom encode opts (not cached)" => fn ->
          ToonEx.Encode.Options.validate!(indent: 4, delimiter: "\t")
        end,
        "validate custom decode opts (not cached)" => fn ->
          ToonEx.Decode.Options.validate!(keys: :atoms, indent_size: 4)
        end,
      },
      time: 5,
      memory_time: 2,
      reduction_time: 1
    )
  end
end

BenchOptions.run()
