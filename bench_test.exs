# Simple benchmark to test performance improvements
# Run with: mix run bench_test.exs

Mix.install([
  {:benchee, "~> 1.0"},
  {:toon_ex, path: "."}
])

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

Benchee.run(
  %{
    "encode small object" => fn -> ToonEx.encode!(small_object) end,
    "encode medium object" => fn -> ToonEx.encode!(medium_object) end,
    "encode large array (1000 items)" => fn -> ToonEx.encode!(large_array) end,
    "encode tabular data (500 rows)" => fn -> ToonEx.encode!(tabular_data) end,
    "decode simple object" => fn -> ToonEx.decode!("%{name: Alice, age: 30}") end,
    "decode array" => fn -> ToonEx.decode!("[3]: a,b,c") end,
    "decode tabular" => fn ->
      ToonEx.decode!("[3]{id,name,age}:\n1,Alice,30\n2,Bob,25\n3,Carol,35")
    end,
    "roundtrip small object" => fn -> ToonEx.decode!(ToonEx.encode!(small_object)) end,
    "roundtrip medium object" => fn -> ToonEx.decode!(ToonEx.encode!(medium_object)) end,
  },
  time: 5,
  memory_time: 2,
  reduction_time: 1
)
