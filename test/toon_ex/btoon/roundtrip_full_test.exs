defmodule ToonEx.Btoon.Roundtrip.FullTest do
  @moduledoc """
  Exhaustive roundtrip: encode(x) |> decode() == x for all value shapes.

  Every test follows the same pattern — the assertion is always:
    decoded == input

  This ensures the encoder and decoder agree on every type and nesting depth.
  """
  use ExUnit.Case, async: true

  alias ToonEx.Btoon

  defp assert_rt(value, opts \\ []) do
    decoded = Btoon.decode!(Btoon.encode!(value, opts))

    assert decoded == value,
           "Roundtrip failed\nInput:   #{inspect(value)}\nDecoded: #{inspect(decoded)}"
  end

  # ── primitives ───────────────────────────────────────────────────────────────

  describe "primitives" do
    test "nil" do
      assert_rt(nil)
    end

    test "true" do
      assert_rt(true)
    end

    test "false" do
      assert_rt(false)
    end

    test "zero" do
      assert_rt(0)
    end

    test "positive integer" do
      assert_rt(42)
    end

    test "negative integer" do
      assert_rt(-17)
    end

    test "large integer" do
      assert_rt(999_999_999)
    end

    test "float" do
      assert_rt(3.14)
    end

    test "negative float" do
      assert_rt(-2.5)
    end

    test "whole float" do
      assert_rt(1.0)
    end

    test "empty string" do
      assert_rt("")
    end

    test "simple string" do
      assert_rt("hello")
    end

    test "string with colon" do
      assert_rt("a:b")
    end

    test "string with bracket" do
      assert_rt("a[1]")
    end

    test "string with newline" do
      assert_rt("line1\nline2")
    end

    test "string with backslash" do
      assert_rt("a\\b")
    end

    test "string with tab" do
      assert_rt("a\tb")
    end

    test "negative zero is numerically zero" do
      assert_rt(-0.0)
    end

    test "small float" do
      assert_rt(1.0e-10)
    end

    test "large float" do
      assert_rt(1.234_567_89e15)
    end
  end

  # ── maps ─────────────────────────────────────────────────────────────────────

  describe "maps" do
    test "empty map" do
      assert_rt(%{})
    end

    test "single key" do
      assert_rt(%{"a" => 1})
    end

    test "multiple keys" do
      assert_rt(%{"a" => 1, "b" => 2})
    end

    test "atom keys encode as strings and decode back" do
      decoded = Btoon.decode!(Btoon.encode!(%{a: 1, b: 2}))
      assert decoded == %{"a" => 1, "b" => 2}
    end

    test "nested map 1 level" do
      assert_rt(%{"a" => %{"b" => 1}})
    end

    test "nested map 2 levels" do
      assert_rt(%{"a" => %{"b" => %{"c" => 1}}})
    end

    test "nested map 5 levels" do
      assert_rt(%{"a" => %{"b" => %{"c" => %{"d" => %{"e" => 42}}}}})
    end

    test "mixed value types" do
      assert_rt(%{"s" => "hi", "n" => 1, "f" => 1.5, "b" => true, "nil" => nil})
    end

    test "empty nested map" do
      assert_rt(%{"x" => %{}})
    end

    test "key with dot" do
      assert_rt(%{"a.b" => 1})
    end

    test "key requiring quotes" do
      assert_rt(%{"full name" => "Alice"})
    end

    test "sibling after nested" do
      assert_rt(%{"user" => %{"name" => "Bob"}, "active" => true})
    end

    test "integer keys are stringified" do
      decoded = Btoon.decode!(Btoon.encode!(%{1 => "one", 2 => "two"}))
      assert decoded == %{"1" => "one", "2" => "two"}
    end
  end

  # ── lists ────────────────────────────────────────────────────────────────────

  describe "lists" do
    test "empty list" do
      assert_rt([])
    end

    test "list of integers" do
      assert_rt([1, 2, 3])
    end

    test "list of strings" do
      assert_rt(["a", "b", "c"])
    end

    test "list of booleans" do
      assert_rt([true, false])
    end

    test "list of nulls" do
      assert_rt([nil, nil])
    end

    test "list of atoms encodes as strings" do
      assert Btoon.decode!(Btoon.encode!([:a, :b])) == ["a", "b"]
    end

    test "mixed primitive list" do
      assert_rt([1, "two", nil, true])
    end

    test "list with empty object" do
      assert_rt([%{}, 1, %{}])
    end

    test "list of maps same keys" do
      assert_rt([%{"x" => 1, "y" => 2}, %{"x" => 3, "y" => 4}])
    end

    test "list of maps diff keys" do
      assert_rt([%{"a" => 1}, %{"b" => 2}])
    end

    test "list of maps with nested values" do
      assert_rt([%{"id" => 1, "meta" => %{"x" => 1}}, %{"id" => 2, "meta" => %{"x" => 2}}])
    end

    test "nested lists 2 levels" do
      assert_rt([[1, 2], [3, 4]])
    end

    test "nested lists 3 levels" do
      assert_rt([[[1]]])
    end

    test "nested lists 4 levels" do
      assert_rt([[[[1]]]])
    end

    test "nested lists 5 levels" do
      assert_rt([[[[[1]]]]])
    end

    test "nested lists mixed depths" do
      assert_rt([[1], [[2]], [[[3]]]])
    end

    test "empty nested lists" do
      assert_rt([[]])
    end

    test "double empty nested" do
      assert_rt([[[]]])
    end

    test "sibling empty lists" do
      assert_rt([[], []])
    end

    test "map inside list" do
      assert_rt([%{"a" => 1, "b" => 2}])
    end

    test "list inside map" do
      assert_rt(%{"items" => [1, 2, 3]})
    end

    test "list inside nested map" do
      assert_rt(%{"a" => %{"items" => ["x", "y"]}})
    end
  end

  # ── typed arrays and object tables ───────────────────────────────────────────

  describe "typed arrays and object tables" do
    test "homogeneous numeric lists round-trip as lists" do
      assert_rt([1, 2, 3])
      assert_rt([1, 300])
      assert_rt([1.5, 2.5])
      assert_rt([1, -2_147_483_648])
      assert_rt([1, 9_223_372_036_854_775_807])
    end

    test "empty list is not a typed array" do
      assert_rt([])
    end

    test "single-element numeric list" do
      assert_rt([7])
      assert_rt([7.5])
    end

    test "tabular array of maps round-trips" do
      assert_rt([
        %{"x" => 1, "y" => 2.5, "s" => "a"},
        %{"x" => 3, "y" => 4.5, "s" => "b"}
      ])
    end

    test "list of maps with nested group round-trips" do
      assert_rt([
        %{"id" => 1, "customer" => %{"name" => "Cust 1", "country" => "DK"}, "total" => 1.5},
        %{"id" => 2, "customer" => %{"name" => "Cust 2", "country" => "US"}, "total" => 3.0}
      ])
    end
  end

  # ── schema mode ──────────────────────────────────────────────────────────────

  describe "schema mode" do
    test "schema-encoded values round-trip with and without embedded schema" do
      schema =
        Btoon.Schema.new(7, "T", [
          %{name: "id", type: :int32},
          %{name: "name", type: :string},
          %{name: "score", type: :float32}
        ])

      value = %{"id" => 3, "name" => "hero", "score" => 1.5}

      assert Btoon.decode!(Btoon.encode!(value, schema: schema)) == value
    end
  end

  # ── option variants ───────────────────────────────────────────────────────────

  describe "option variants" do
    test "string_table: :off round-trips" do
      assert_rt(%{"name" => "Alice", "tags" => ["a", "b"]}, string_table: :off)
    end

    test "typed_arrays: false round-trips" do
      assert_rt([1, 2, 3], typed_arrays: false)
    end

    test "object_tables: false round-trips" do
      assert_rt([%{"x" => 1}, %{"x" => 2}], object_tables: false)
    end

    test "keys: :atoms on decode" do
      value = %{"name" => "Alice", "age" => 30}
      bin = Btoon.encode!(value)
      assert Btoon.decode!(bin, keys: :atoms) == %{name: "Alice", age: 30}
    end

    test "dictionary session round-trips" do
      dict = Btoon.Dictionary.new(["name"])
      value = %{"name" => "Alice", "extra" => "value"}
      bin = Btoon.encode!(value, dictionary: dict)

      assert Btoon.decode!(bin, dictionary: dict) == value
    end
  end
end
