# Benchmark for decode improvements (D2, D3, D5, D7)
# Run with: MIX_ENV=dev mix run bench/bench_decode.exs

defmodule BenchDecode do
  @moduledoc false

  def run do
    # Test data
    simple_obj = "name: Alice\nage: 30"
    nested_obj = "user:\n  name: Alice\n  age: 30\n  address:\n    city: NYC\n    zip: 10001"
    array_obj = "tags[3]: a,b,c"
    tabular_obj = "[3]{age,id,name}:\n  30,1,Alice\n  25,2,Bob\n  35,3,Carol"
    nested_array = "items[2]:\n  - name: item1\n    value: 10\n  - name: item2\n    value: 20"
    
    # Custom indent_size (tests D2 - Fast.Decoder handles custom indent)
    # Using 4-space indent for nested levels (multiple of indent_size)
    custom_indent = "user:\n    name: Alice\n    age: 30\n    address:\n        city: NYC\n        zip: 10001"

    Benchee.run(
      %{
        "decode simple object" => fn -> ToonEx.decode!(simple_obj) end,
        "decode nested object" => fn -> ToonEx.decode!(nested_obj) end,
        "decode array" => fn -> ToonEx.decode!(array_obj) end,
        "decode tabular" => fn -> ToonEx.decode!(tabular_obj) end,
        "decode nested array" => fn -> ToonEx.decode!(nested_array) end,
        "decode with custom indent (4 spaces)" => fn -> ToonEx.decode!(custom_indent, indent_size: 4) end,
      },
      time: 5,
      memory_time: 2,
      reduction_time: 1
    )
  end
end

BenchDecode.run()
