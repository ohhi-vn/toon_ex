defmodule ToonEx.RoundtripTest do
  @moduledoc """
  Roundtrip tests verifying decode(encode(x)) == normalize(x).

  Coverage:
  - All primitive types
  - Container types (list, map, struct) at various nesting depths
  - Struct encoder variations (explicit vs derived)
  - Decoder edge cases (empty content, nested arrays)
  """
  use ExUnit.Case, async: true

  alias ToonEx.Fixtures.{Company, CustomDate, Person, UserWithExcept}

  # Helper to test encode/decode roundtrip
  defp roundtrip(value) do
    encoded = ToonEx.encode!(value)
    {:ok, decoded} = ToonEx.decode(encoded)
    normalized = ToonEx.Utils.normalize(value)
    {encoded, decoded, normalized}
  end

  defp assert_roundtrip(value) do
    {_encoded, decoded, normalized} = roundtrip(value)

    assert decoded == normalized,
           "Roundtrip failed.\nInput: #{inspect(value)}\nNormalized: #{inspect(normalized)}\nDecoded: #{inspect(decoded)}"
  end

  describe "primitive types" do
    test "nil" do
      assert_roundtrip(nil)
    end

    test "booleans" do
      assert_roundtrip(true)
      assert_roundtrip(false)
    end

    test "integers" do
      assert_roundtrip(0)
      assert_roundtrip(42)
      assert_roundtrip(-17)
      assert_roundtrip(1_000_000)
    end

    test "floats" do
      assert_roundtrip(3.14)
      assert_roundtrip(-2.5)
      assert_roundtrip(0.0)
    end

    test "strings" do
      assert_roundtrip("")
      assert_roundtrip("hello")
      assert_roundtrip("hello world")
      assert_roundtrip("special: []{},")
    end

    test "atoms convert to strings" do
      {_enc, decoded, normalized} = roundtrip(:status)
      assert normalized == "status"
      assert decoded == "status"
    end
  end

  describe "lists" do
    test "empty list" do
      assert_roundtrip([])
    end

    test "list of primitives" do
      assert_roundtrip([1, 2, 3])
      assert_roundtrip(["a", "b", "c"])
      assert_roundtrip([true, false, nil])
    end

    test "list of atoms" do
      {_enc, decoded, normalized} = roundtrip([:a, :b, :c])
      assert normalized == ["a", "b", "c"]
      assert decoded == ["a", "b", "c"]
    end

    test "mixed type list" do
      {_enc, decoded, normalized} = roundtrip([1, "two", :three, nil])
      assert normalized == [1, "two", "three", nil]
      assert decoded == normalized
    end

    test "mixed type list with empty object" do
      input = [1, "two", "three", %{}, nil, %{}]
      {_enc, decoded, normalized} = roundtrip(input)
      assert normalized == input
      assert decoded == normalized
    end

    test "mixed type list with map object" do
      input = [%{"a" => %{}, "b" => "b1"}]
      expected = [%{"a" => %{}, "b" => "b1"}]
      {_enc, decoded, normalized} = roundtrip(input)

      assert normalized == expected
      assert decoded == normalized
    end

    test "mixed type list with map object 2" do
      input = [%{"a" => "a1", "b" => %{}}]
      expected = [%{"a" => "a1", "b" => %{}}]
      {_enc, decoded, normalized} = roundtrip(input)

      assert normalized == expected
      assert decoded == normalized
    end

    test "nested lists (2 levels)" do
      assert_roundtrip([[1, 2], [3, 4]])
    end

    test "nested lists (3 levels)" do
      assert_roundtrip([[[1]]])
    end

    test "nested lists (4 levels)" do
      assert_roundtrip([[[[1]]]])
    end

    test "nested lists (5 levels)" do
      assert_roundtrip([[[[[1]]]]])
    end

    test "nested lists with mixed depths" do
      assert_roundtrip([[1], [[2]], [[[3]]]])
    end

    test "multiple empty nested lists at same level" do
      assert_roundtrip([[], []])
      assert_roundtrip([[[], []]])
    end

    test "empty nested lists" do
      assert_roundtrip([[]])
      assert_roundtrip([[[]]])
    end

    test "list of maps" do
      assert_roundtrip([%{"x" => 1}, %{"x" => 2}])
    end

    test "list of maps with atom values" do
      {_enc, decoded, normalized} = roundtrip([%{"status" => :a}, %{"status" => :b}])
      assert normalized == [%{"status" => "a"}, %{"status" => "b"}]
      assert decoded == normalized
    end
  end

  describe "maps" do
    test "empty map" do
      assert_roundtrip(%{})
    end

    test "string keys" do
      assert_roundtrip(%{"name" => "Alice", "age" => 30})
    end

    test "atom keys convert to strings" do
      {_enc, decoded, normalized} = roundtrip(%{name: "Alice", age: 30})
      assert normalized == %{"name" => "Alice", "age" => 30}
      assert decoded == normalized
    end

    test "atom values convert to strings" do
      {_enc, decoded, normalized} = roundtrip(%{"status" => :active})
      assert normalized == %{"status" => "active"}
      assert decoded == normalized
    end

    test "nested maps" do
      assert_roundtrip(%{"a" => %{"b" => %{"c" => 1}}})
    end

    test "map with list value" do
      assert_roundtrip(%{"items" => [1, 2, 3]})
    end

    test "map with list of atoms" do
      {_enc, decoded, normalized} = roundtrip(%{"tags" => [:a, :b]})
      assert normalized == %{"tags" => ["a", "b"]}
      assert decoded == normalized
    end

    test "deeply nested with atoms throughout" do
      input = %{
        level1: %{
          level2: %{
            status: :active,
            tags: [:a, :b]
          }
        }
      }

      {_enc, decoded, normalized} = roundtrip(input)

      expected = %{
        "level1" => %{
          "level2" => %{
            "status" => "active",
            "tags" => ["a", "b"]
          }
        }
      }

      assert normalized == expected
      assert decoded == expected
    end
  end

  describe "structs with @derive" do
    test "simple struct" do
      person = %Person{name: "Alice", age: 30}
      assert_roundtrip(person)
    end

    test "struct with nil field" do
      person = %Person{name: "Alice", age: nil}
      assert_roundtrip(person)
    end

    test "struct with except option" do
      user = %UserWithExcept{name: "Alice", email: "a@b.com", password: "secret"}
      {_enc, decoded, normalized} = roundtrip(user)
      # password should be excluded
      assert normalized == %{"name" => "Alice", "email" => "a@b.com"}
      assert decoded == normalized
    end

    test "nested struct (Company with Person ceo)" do
      company = %Company{name: "Acme", ceo: %Person{name: "Bob", age: 45}}
      {_enc, decoded, normalized} = roundtrip(company)
      expected = %{"name" => "Acme", "ceo" => %{"name" => "Bob", "age" => 45}}
      assert normalized == expected
      assert decoded == expected
    end

    test "deeply nested structs" do
      # Company -> Person as ceo, but Person could have nested data
      company = %Company{
        name: "Acme",
        ceo: %Person{name: "Alice", age: 40}
      }

      assert_roundtrip(company)
    end

    test "list of structs" do
      people = [
        %Person{name: "Alice", age: 30},
        %Person{name: "Bob", age: 25}
      ]

      assert_roundtrip(people)
    end

    test "struct inside map" do
      data = %{"employee" => %Person{name: "Charlie", age: 35}}
      assert_roundtrip(data)
    end

    test "map inside struct field" do
      # Person doesn't have a map field, use Company with a map as ceo
      company = %Company{name: "Test", ceo: %{"title" => "CEO", "level" => 1}}
      assert_roundtrip(company)
    end
  end

  test "list of mix maps" do
    people = [
      %{},
      %{name: "Bob", age: 25},
      %{}
    ]

    assert_roundtrip(people)
  end

  test "list of mix elements" do
    people = [
      1,
      "Hello",
      %{},
      %{name: "Bob", age: 25},
      [1, 2, 4]
    ]

    assert_roundtrip(people)
  end

  test "list of mix elements 2" do
    people = [nil, "1", "room:lobby", "phx_join", %{}]

    assert_roundtrip(people)
  end

  describe "structs with explicit encoder" do
    test "custom date encoder returns string" do
      date = %CustomDate{year: 2024, month: 1, day: 15}
      {_enc, decoded, normalized} = roundtrip(date)
      # CustomDate encodes to "2024-01-15" string
      assert normalized == "2024-01-15"
      assert decoded == "2024-01-15"
    end

    test "custom date in map" do
      data = %{"date" => %CustomDate{year: 2024, month: 12, day: 25}}
      {_enc, decoded, normalized} = roundtrip(data)
      assert normalized == %{"date" => "2024-12-25"}
      assert decoded == normalized
    end

    test "custom date in list" do
      dates = [
        %CustomDate{year: 2024, month: 1, day: 1},
        %CustomDate{year: 2024, month: 12, day: 31}
      ]

      {_enc, decoded, normalized} = roundtrip(dates)
      assert normalized == ["2024-01-01", "2024-12-31"]
      assert decoded == normalized
    end
  end

  describe "edge cases from past bugs" do
    test "struct with atom field values should convert atoms" do
      # This was a bug - atoms in struct fields weren't converted
      # Using a map since our test structs don't have atom fields
      data = %{"config" => %{"mode" => :production, "flags" => [:a, :b]}}
      {_enc, decoded, normalized} = roundtrip(data)
      expected = %{"config" => %{"mode" => "production", "flags" => ["a", "b"]}}
      assert normalized == expected
      assert decoded == expected
    end

    test "nested struct returning map should be recursively normalized" do
      # PR #3 bug: derived encoders returned TOON strings causing double-escaping
      company = %Company{name: "Test", ceo: %Person{name: "Boss", age: 50}}
      encoded = ToonEx.encode!(company)
      # Should NOT contain escaped quotes or double-encoded content
      refute String.contains?(encoded, "\\\"")
      refute String.contains?(encoded, "\\n")
    end

    test "list of maps with non-primitive values uses list format not tabular" do
      # Maps with nested values should not use tabular format
      data = [
        %{"id" => 1, "meta" => %{"x" => 1}},
        %{"id" => 2, "meta" => %{"x" => 2}}
      ]

      encoded = ToonEx.encode!(data)
      # Should use list format (hyphen markers) not tabular format (no braces in header)
      assert String.contains?(encoded, "- ")
    end
  end

  describe "decoder edge cases" do
    test "empty string decodes to empty map" do
      assert {:ok, %{}} = ToonEx.decode("")
    end

    test "whitespace-only string decodes to empty map" do
      assert {:ok, %{}} = ToonEx.decode("   ")
      assert {:ok, %{}} = ToonEx.decode("\n\n")
      assert {:ok, %{}} = ToonEx.decode("  \n  \n  ")
    end

    test "nested array followed by sibling primitive" do
      toon = "[2]:\n  - [1]:\n    - inner\n  - outer"
      {:ok, decoded} = ToonEx.decode(toon)
      assert decoded == [["inner"], "outer"]
    end

    test "mixed empty and non-empty nested arrays" do
      toon = "[3]:\n  - [0]:\n  - [1]:\n    - 42\n  - [0]:"
      {:ok, decoded} = ToonEx.decode(toon)
      assert decoded == [[], [42], []]
    end

    test "multiple nested arrays with content" do
      toon = "[2]:\n  - [2]:\n    - a\n    - b\n  - [2]:\n    - c\n    - d"
      {:ok, decoded} = ToonEx.decode(toon)
      assert decoded == [["a", "b"], ["c", "d"]]
    end

    test "empty array header with no nested content" do
      # Tests parse_nested_list_array empty branch: [0]: at end of input
      toon = "[1]:\n  - [0]:"
      {:ok, decoded} = ToonEx.decode(toon)
      assert decoded == [[]]
    end
  end

  describe "encoder format edge cases" do
    test "empty list encodes with zero-length header" do
      result = ToonEx.encode!(%{"items" => []})
      # §9.1: empty arrays use the `key: []` value form
      assert result =~ "items: []"
    end

    test "nested empty structures" do
      # Empty map inside map - produces key with colon
      assert "nested:" = ToonEx.encode!(%{"nested" => %{}})

      # Empty list inside map
      result = ToonEx.encode!(%{"items" => []})
      assert result =~ "items: []"
    end

    test "list of maps with same keys uses tabular format" do
      data = [
        %{"id" => "1", "name" => "Alice"},
        %{"id" => "2", "name" => "Bob"}
      ]

      encoded = ToonEx.encode!(data)
      {:ok, decoded} = ToonEx.decode(encoded)

      assert decoded == data
      # Tabular format uses braces in header, no hyphen markers
      assert String.contains?(encoded, "]{")
      refute String.contains?(encoded, "- ")
    end

    test "list of maps with integer values uses tabular format" do
      data = [
        %{"x" => 1, "y" => 2},
        %{"x" => 3, "y" => 4}
      ]

      encoded = ToonEx.encode!(data)
      {:ok, decoded} = ToonEx.decode(encoded)

      assert decoded == data
      # Tabular format for primitive integer values
      assert String.contains?(encoded, "]{")
    end
  end

  test "very small float roundtrips correctly" do
    data = %{"x" => 1.0e-10}
    {encoded, decoded, normalized} = roundtrip(data)
    refute String.contains?(encoded, "e"), "should not use scientific notation"
    assert_in_delta decoded["x"], normalized["x"], 1.0e-20
  end

  test "very large float roundtrips correctly" do
    data = %{"x" => 1.234_567_89e15}
    {_encoded, decoded, normalized} = roundtrip(data)
    assert decoded["x"] == normalized["x"]
  end
end
