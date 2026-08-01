defmodule BenchData do
  @moduledoc """
  Centralized test data for benchmarks.
  
  Provides realistic data structures covering common use cases:
  - Small/medium/large objects with various nesting levels
  - Arrays: primitive, tabular (uniform objects), list (mixed)
  - Edge cases: deeply nested, escapes, empty structures
  """

  @doc "Small flat object (~50 bytes)"
  def small_object do
    %{"name" => "Alice", "age" => 30, "active" => true}
  end

  @doc "Medium object with nested structure (~500 bytes)"
  def medium_object do
    %{
      "id" => 12_345,
      "name" => "Bob Smith",
      "email" => "bob@example.com",
      "active" => true,
      "score" => 98.5,
      "tags" => ["elixir", "toon", "llm", "encoding"],
      "address" => %{
        "street" => "123 Main St",
        "city" => "Portland",
        "state" => "OR",
        "zip" => "97201"
      }
    }
  end

  @doc "Large object with deep nesting (~3KB)"
  def large_object do
    %{
      "user" => %{
        "id" => 98_765,
        "name" => "Charlie Brown",
        "email" => "charlie@example.com",
        "created_at" => "2024-01-15T10:30:00Z",
        "profile" => %{
          "bio" => "Software engineer passionate about Elixir and functional programming",
          "avatar_url" => "https://example.com/avatars/charlie.jpg",
          "website" => "https://charlie.dev",
          "location" => "San Francisco, CA"
        },
        "settings" => %{
          "theme" => "dark",
          "notifications" => true,
          "language" => "en",
          "timezone" => "America/Los_Angeles"
        }
      },
      "projects" => [
        %{"name" => "ToonEx", "description" => "High-performance TOON encoder/decoder", "stars" => 1250, "language" => "Elixir", "tags" => ["encoding", "decoding", "performance"]},
        %{"name" => "PhoenixApp", "description" => "Real-time web application", "stars" => 890, "language" => "Elixir", "tags" => ["web", "real-time", "channels"]},
        %{"name" => "DataPipeline", "description" => "ETL pipeline for analytics", "stars" => 456, "language" => "Python", "tags" => ["data", "etl", "analytics"]}
      ],
      "metrics" => %{"requests" => 1_234_567, "errors" => 42, "latency_p99" => 125.5, "uptime" => 99.99}
    }
  end

  @doc "Primitive array (100 items)"
  def primitive_array_100 do
    Enum.map(1..100, &"item_#{&1}")
  end

  @doc "Primitive array (1000 items)"
  def primitive_array_1000 do
    Enum.map(1..1000, &"item_#{&1}")
  end

  @doc "Tabular array - uniform objects (50 rows)"
  def tabular_array_50 do
    Enum.map(1..50, fn i ->
      %{"id" => i, "name" => "User_#{i}", "email" => "user#{i}@example.com", "score" => :rand.uniform(100), "active" => rem(i, 2) == 0}
    end)
  end

  @doc "Tabular array - uniform objects (500 rows)"
  def tabular_array_500 do
    Enum.map(1..500, fn i ->
      %{"id" => i, "name" => "User_#{i}", "email" => "user#{i}@example.com", "score" => :rand.uniform(100), "active" => rem(i, 2) == 0}
    end)
  end

  @doc "Tabular array - uniform objects (1000 rows)"
  def tabular_array_1000 do
    Enum.map(1..1000, fn i ->
      %{"id" => i, "name" => "User_#{i}", "email" => "user#{i}@example.com", "score" => :rand.uniform(100), "active" => rem(i, 2) == 0}
    end)
  end

  @doc "List array - mixed objects (20 items)"
  def list_array_20 do
    Enum.map(1..20, fn i ->
      if rem(i, 3) == 0 do
        %{"type" => "complex", "data" => %{"nested" => %{"value" => i, "items" => ["a", "b", "c"]}}}
      else
        %{"type" => "simple", "value" => i, "tags" => ["tag_#{i}"]}
      end
    end)
  end

  @doc "Deeply nested object (5 levels)"
  def deeply_nested do
    %{
      "level1" => %{
        "level2" => %{
          "level3" => %{
            "level4" => %{
              "level5" => %{
                "value" => "deep",
                "numbers" => [1, 2, 3, 4, 5],
                "metadata" => %{"created" => "2024-01-01", "version" => 2}
              }
            }
          }
        }
      }
    }
  end

  @doc "String with various escapes"
  def string_with_escapes do
    %{"message" => "Hello \"World\"\nNew line\tTabbed\\Backslash", "path" => "C:\\Users\\test\\file.txt"}
  end

  @doc "Empty structures"
  def empty_object, do: %{}
  def empty_array, do: []

  @doc "Encode data to TOON string for decode benchmarks"
  def toon_string(data), do: ToonEx.encode!(data)

  @doc "Encode data to JSON string for comparison"
  def json_string(data), do: JSON.encode!(data)

  @doc "All encoding inputs with labels"
  def encode_inputs do
    %{
      "small_object" => small_object(),
      "medium_object" => medium_object(),
      "large_object" => large_object(),
      "deeply_nested" => deeply_nested(),
      "string_with_escapes" => string_with_escapes(),
      "empty_object" => empty_object(),
      "primitive_array_100" => primitive_array_100(),
      "primitive_array_1000" => primitive_array_1000(),
      "tabular_array_50" => tabular_array_50(),
      "tabular_array_500" => tabular_array_500(),
      "tabular_array_1000" => tabular_array_1000(),
      "list_array_20" => list_array_20(),
      "empty_array" => empty_array()
    }
  end

  @doc "All decode inputs with labels (pre-encoded TOON)"
  def decode_inputs do
    encode_inputs()
    |> Enum.map(fn {k, v} -> {k, toon_string(v)} end)
    |> Enum.into(%{})
  end

  @doc "All roundtrip inputs with labels"
  def roundtrip_inputs do
    encode_inputs()
    |> Map.take(["small_object", "medium_object", "large_object", "primitive_array_100", "tabular_array_50", "tabular_array_500", "list_array_20", "deeply_nested"])
  end
end