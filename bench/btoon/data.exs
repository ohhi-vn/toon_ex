defmodule BtoonBenchData do
  @moduledoc """
  Centralized test data for BTOON benchmarks.

  Provides realistic data structures covering common use cases:
  - Small/medium/large objects with various nesting levels
  - Tabular arrays (uniform objects)
  - Deeply nested structures
  - Strings with escapes
  """

  @doc "Small flat object (~50 bytes)"
  def small_object, do: %{"name" => "Alice", "age" => 30, "active" => true}

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
        "profile" => %{
          "bio" => "Software engineer passionate about Elixir and functional programming",
          "avatar_url" => "https://example.com/avatars/charlie.jpg",
          "location" => "San Francisco, CA"
        },
        "settings" => %{
          "theme" => "dark",
          "notifications" => true,
          "language" => "en",
          "timezone" => "America/Los_Angeles"
        }
      },
      "projects" =>
        Enum.map(1..10, fn i ->
          %{
            "name" => "Project #{i}",
            "description" => "Description for project #{i}",
            "stars" => i * 100,
            "language" => "Elixir"
          }
        end)
    }
  end

  @doc "Tabular array - uniform objects (100 rows)"
  def tabular_array_100 do
    Enum.map(1..100, fn i ->
      %{
        "id" => i,
        "name" => "User_#{i}",
        "email" => "user#{i}@example.com",
        "score" => :rand.uniform(100),
        "active" => rem(i, 2) == 0
      }
    end)
  end

  @doc "Tabular array - uniform objects (500 rows)"
  def tabular_array_500 do
    Enum.map(1..500, fn i ->
      %{
        "id" => i,
        "name" => "User_#{i}",
        "email" => "user#{i}@example.com",
        "score" => :rand.uniform(100),
        "active" => rem(i, 2) == 0
      }
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
    %{
      "message" => "Hello \"World\"\nNew line\tTabbed\\Backslash",
      "path" => "C:\\Users\\test\\file.txt"
    }
  end

  @doc "All datasets as {label, data} pairs"
  def datasets do
    [
      {"Small object", small_object()},
      {"Medium object", medium_object()},
      {"Large object", large_object()},
      {"Tabular array (100 rows)", tabular_array_100()},
      {"Tabular array (500 rows)", tabular_array_500()},
      {"Deeply nested", deeply_nested()},
      {"String escapes", string_with_escapes()}
    ]
  end

  @doc "Encode data to BTOON binary"
  def btoon_binary(data), do: ToonEx.Btoon.encode!(data)

  @doc "Encode data to TOON text"
  def toon_string(data), do: ToonEx.encode!(data)

  @doc "Encode data to JSON text"
  def json_string(data), do: JSON.encode!(data)
end
