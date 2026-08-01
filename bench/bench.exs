# Simple benchmark to test performance improvements
# Run with: MIX_ENV=dev mix run bench/bench.exs

defmodule Bench do
  @moduledoc false

  def run do
    # Test data
    small_object = %{"name" => "Alice", "age" => 30, "city" => "NYC"}
    medium_object = %{
      "id" => 1,
      "name" => "Test User",
      "email" => "test@example.com",
      "roles" => ["admin", "user"],
      "metadata" => %{"created" => "2024-01-01", "updated" => "2024-01-15"},
      "tags" => ["elixir", "performance", "toon"]
    }

    large_array = Enum.map(1..1000, fn i ->
      %{
        "id" => i,
        "name" => "Item #{i}",
        "value" => i * 10,
        "active" => rem(i, 2) == 0
      }
    end)

    tabular_data = Enum.map(1..500, fn i ->
      %{
        "id" => i,
        "name" => "User #{i}",
        "email" => "user#{i}@example.com",
        "age" => 20 + rem(i, 50),
        "city" => Enum.at(["NYC", "LA", "Chicago", "Houston", "Phoenix"], rem(i, 5))
      }
    end)

    # Valid TOON inputs (matching encoder output format)
    tabular_input = "[3]{age,id,name}:\n  30,1,Alice\n  25,2,Bob\n  35,3,Carol"
    array_input = "[3]: a,b,c"
    object_input = "name: Alice\nage: 30"

    Benchee.run(
      %{
        "encode small object" => fn -> ToonEx.encode!(small_object) end,
        "encode medium object" => fn -> ToonEx.encode!(medium_object) end,
        "encode large array (1000 items)" => fn -> ToonEx.encode!(large_array) end,
        "encode tabular data (500 rows)" => fn -> ToonEx.encode!(tabular_data) end,
        "decode simple object" => fn -> ToonEx.decode!(object_input) end,
        "decode array" => fn -> ToonEx.decode!(array_input) end,
        "decode tabular" => fn -> ToonEx.decode!(tabular_input) end,
        "roundtrip small object" => fn -> ToonEx.decode!(ToonEx.encode!(small_object)) end,
        "roundtrip medium object" => fn -> ToonEx.decode!(ToonEx.encode!(medium_object)) end,
      },
      time: 5,
      memory_time: 2,
      reduction_time: 1
    )
  end
end

Bench.run()
